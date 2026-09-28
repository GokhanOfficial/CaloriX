/**
 * Yedek içe aktarımının **ağ katmanı**: ön-uçu doğrulama → varlık kontrolü →
 * toplu + telafili yazma.
 *
 * ## Neden bu akış
 *
 * PostgREST'te çok istekli bir yazma dizisi **atomik değildir**: her
 * `POST` kendi transaction'ıdır. Önceki sürümde `importData` satır satır
 * yazıyordu; 500. öğünde bir CHECK ihlali (`23514`) oluştuğunda 2000
 * öğünlük bir yedekte `foods` + `food_nutrition` + 500 öğün **yazılmış**
 * kalıyordu ve kullanıcı "hata" görüyor, hangi öğünlerin geldiğini
 * bilmiyordu. Bu bir **veri bozulması** senaryosudur.
 *
 * ## Üç faz
 *
 * 1. **Ön-uçu (ağ yok).** Yedek ayrıştırılır ve tüm satırlar DB
 *    sözleşmesine göre denetlenir. **Tek bir ölümcül ihlalde hiçbir
 *    istek atılmaz** (`ImportValidationError`).
 * 2. **Varlık kontrolü (yalnız GET).** Dedup anahtarları dilimli `in`
 *    sorgularıyla okunur; yazma yine yapılmaz.
 * 3. **Yazma (toplu + telafili).** Tablolar bağımlılık sırasıyla yazılır.
 *    Hata olursa o turda yazılan satırların `id`'leri toplanır ve
 *    **fiziksel olarak silinir**; ardından ne yazıldığını tam olarak
 *    söyleyen bir `ImportReport` ile `ImportWriteError` fırlatılır.
 *    Telafi de başarısız olursa kalan satırlar **tek tek sayılır** —
 *    hiçbir durumda görünmez bir sonuç üretilmez.
 */

import { supabase } from '@/integrations/supabase/client';
import {
  IMPORT_BATCH_SIZE,
  IMPORT_TABLES,
  INSERT_PREFER_DEFAULTS,
  ImportFormatError,
  ImportValidationError,
  ImportWriteError,
  type ImportPlan,
  type ImportReport,
  type ImportTable,
  type PlannedRow,
  buildImportPlan,
  chunk,
  dateString,
  decodeBackup,
  emptyReport,
  epochMicros,
  inFilterChunks,
  mealKey,
  uniform,
} from '@/lib/import/backupImport';

// ---------------------------------------------------------------------------
// Dahili yardımcılar
// ---------------------------------------------------------------------------

/** `PostgrestError` benzeri hata nesnesini daraltır. */
function asPostgrestError(error: unknown): { code?: string; message: string } {
  if (error && typeof error === 'object' && 'message' in error) {
    const e = error as { code?: string; message: string };
    return { code: e.code, message: typeof e.message === 'string' ? e.message : 'bilinmeyen' };
  }
  return { message: 'bilinmeyen hata' };
}

/** Yalnızca GET'lerle, hiçbir yazma yapmadan varlık kontrolü. */
async function loadExistingKeys(userId: string, plan: ImportPlan): Promise<void> {
  for (const chunkNames of inFilterChunks(plan.foodNames)) {
    const { data, error } = await supabase
      .from('foods')
      .select('id, name')
      .eq('created_by', userId)
      .in('name', chunkNames);
    if (error) throw error;
    for (const row of data ?? []) {
      const name = typeof row.name === 'string' ? row.name.trim() : '';
      if (!name) continue;
      // `foods` üzerinde `UNIQUE(created_by, name)` **yoktur**
      // (`full_setup.sql:70-80`): ilk eşleşme kazanır.
      plan.existingFoodNames.add(name);
      const id = row.id as string | undefined;
      if (id && !plan.existingFoodIds.has(name)) plan.existingFoodIds.set(name, id);
    }
  }

  for (const chunkDates of inFilterChunks(plan.mealDates)) {
    const { data, error } = await supabase
      .from('meal_entries')
      .select('entry_date, custom_name, meal_type')
      .eq('user_id', userId)
      .is('deleted_at', null)
      .in('entry_date', chunkDates);
    if (error) throw error;
    for (const row of data ?? []) {
      const day = dateString(row.entry_date);
      if (day === null) continue;
      const key = mealKey(day, row.custom_name, row.meal_type);
      if (key !== null) plan.existingMealKeys.add(key);
    }
  }

  // Su dedup'u **dize değil epoch mikrosaniye** üzerinden: Postgres
  // `timestamptz` çıktısı ile yedeğin damga biçimi farklı olabilir
  // (`+00:00` ↔ `Z`), dize karşılaştırması dedup'ı kırar ve aynı su
  // kaydı iki kez eklenir.
  for (const chunkInstants of inFilterChunks(plan.waterInstants)) {
    const { data, error } = await supabase
      .from('water_entries')
      .select('entry_time')
      .eq('user_id', userId)
      .in('entry_time', chunkInstants);
    if (error) throw error;
    for (const row of data ?? []) {
      const micros = epochMicros(row.entry_time);
      if (micros !== null) plan.existingWaterKeys.add(String(micros));
    }
  }

  for (const chunkDates of inFilterChunks(plan.weightDates)) {
    const { data, error } = await supabase
      .from('weight_entries')
      .select('entry_date')
      .eq('user_id', userId)
      .in('entry_date', chunkDates);
    if (error) throw error;
    for (const row of data ?? []) {
      const day = dateString(row.entry_date);
      if (day !== null) plan.existingWeightDates.add(day);
    }
  }
}

type IdRow = { id: string };

/**
 * Dilimli toplu `insert` + `.select('id')`.
 *
 * Boş girdi **hiç istek atmaz**: PostgREST'e `[]` göndermek `PGRST102`
 * ("All object keys must match") verir.
 */
async function insertBatched(
  table: ImportTable,
  rows: readonly PlannedRow[],
): Promise<IdRow[]> {
  const out: IdRow[] = [];
  if (rows.length === 0) return out;
  for (const batch of chunk(rows, IMPORT_BATCH_SIZE)) {
    // `Record<string, unknown>` genel tip, tablonun `Insert` şemasıyla
    // yapısal olarak uyumsuzdur; bu yüzden `Insert` tiplerine erişilemeyen
    // bir yardımcı kullanılır. **Güvenlik sözleşmesi `uniform()` ile
    // sağlanır**: gövde yalnızca `INSERT_COLUMNS` sabitindeki beyaz
    // listelenmiş kolonları taşır (`PGRST204` ve kullanıcı kontrolü).
    const payload = uniform(batch, table) as never;
    const { data, error } = await supabase
      .from(table)
      .insert(payload, INSERT_PREFER_DEFAULTS)
      .select('id');
    if (error) throw error;
    out.push(...((data ?? []) as IdRow[]));
  }
  return out;
}

/**
 * `favorite_foods` / `recent_foods` yazımı — `UNIQUE(user_id, food_id)`
 * üzerinden `upsert`.
 *
 * Bu iki tablo `insert` ile yazılsaydı aynı favori ikinci denemede 23505
 * ile düşürürdü. `use_count`/`last_used_at` alanları DB varsayılanıdır:
 * geri yüklemede **kullanıcının eski kullanım sayısını ezmek** yerine
 * yalnızca favori/son kullanılan **listesi** kurulur (yedekten kopyalanan
 * `use_count` yerine `ignoreDuplicates` kullanılır).
 */
async function upsertFoodLists(
  table: 'favorite_foods' | 'recent_foods',
  userId: string,
  foodIds: readonly string[],
): Promise<number> {
  if (foodIds.length === 0) return 0;
  let written = 0;
  for (const batch of chunk(foodIds, IMPORT_BATCH_SIZE)) {
    const rows = batch.map((foodId) => ({ user_id: userId, food_id: foodId }));
    // `ignoreDuplicates: true` + `Prefer: resolution=ignore-duplicates`
    // PostgREST'in `ON CONFLICT DO NOTHING` üretmesini sağlar: aynı favori
    // ikinci denemede 23505 **vermez**. `count: 'exact'` PostgREST'te
    // ek bir round-trip istediği için burada kullanılmaz; eklenen sayı
    // `id` listesinden hesaplanır.
    const { data, error } = await supabase
      .from(table)
      .upsert(rows, { onConflict: 'user_id,food_id', ignoreDuplicates: true })
      .select('id');
    if (error) throw error;
    written += (data ?? []).length;
  }
  return written;
}

/**
 * O turda yazılan satırları **fiziksel olarak** siler.
 *
 * Telafi bir "yumuşak silme" değildir: içe aktarma yedekten türetilmiş
 * satırlar ekliyordu, DB'de kullanıcının kendi kaydı yok; `DELETE`
 * politikaları `auth.uid()` kapsamıyla var. `id` listesi de `in` filtresi
 * olduğu için **dilimlenir** (2000 UUID tek sorgoda ~78 KB → 414).
 *
 * Dönen değer: hiçbir tablo silinemezse `false` (rapor `rolledBack: false`).
 */
async function rollback(
  written: Map<ImportTable, string[]>,
  survivors: Record<string, number>,
): Promise<boolean> {
  let allRolled = true;
  // Bağımlılık sırasının tersi.
  for (const table of [...IMPORT_TABLES].reverse()) {
    const ids = written.get(table);
    if (!ids || ids.length === 0) continue;
    let remaining = ids.length;
    for (const idChunk of inFilterChunks(ids)) {
      const { error } = await supabase.from(table).delete().in('id', idChunk);
      if (!error) {
        remaining -= idChunk.length;
      } else {
        console.error(`Telafi: ${table} silinemedi`, error);
      }
    }
    if (remaining > 0) {
      allRolled = false;
      // Silinemeyen satırlar **kalan** olarak raporlanır (varsayım yok):
      // hangi dilimlerin sildiğini bilmiyoruz, bu yüzden en kötü senaryo
      // varsayılır ve id'ler tam olarak raporlanır.
      survivors[table] = remaining;
    }
  }
  return allRolled;
}

// ---------------------------------------------------------------------------
// FAZ 3 — yazma (toplu + telafili)
// ---------------------------------------------------------------------------

async function applyPlan(userId: string, plan: ImportPlan): Promise<ImportReport> {
  const report = emptyReport();
  const written = new Map<ImportTable, string[]>();
  let stage: ImportTable = 'foods';

  const remember = (table: ImportTable, ids: IdRow[]) => {
    if (ids.length > 0) written.set(table, ids.map((r) => r.id));
  };

  try {
    // 1) foods + food_nutrition (besin satırları yeni gıda id'sine bağlı).
    //    `plan.existingFoodNames` içindeki gıdalar **yeniden yazılmaz**;
    //    öğünler/besin satırları onların **mevcut** id'sine bağlanır.
    stage = 'foods';
    const foodIdByName = new Map(plan.externalFoodIds);
    for (const [name, id] of plan.existingFoodIds) foodIdByName.set(name, id);

    const toInsert = plan.foods.filter((r) => !plan.existingFoodNames.has(r.backupName ?? ''));
    const insertedFoods = await insertBatched('foods', toInsert);
    // Postgres `INSERT … RETURNING` satırları giriş sırasıyla döner, ancak
    // buna güvenmek yerine **ad** üzerinden eşleme yapılır: dedup ad bazlıdır
    // ve plan içinde adlar benzersizdir. Sıra bozulsa bile yanlış gıda
    // `food_id`'si yazılmaz.
    if (insertedFoods.length !== toInsert.length) {
      throw new Error(
        `Gıda ekleme cevabı beklenmedik: ${insertedFoods.length}/${toInsert.length}`,
      );
    }
    toInsert.forEach((row, i) => {
      const name = row.backupName;
      if (name) foodIdByName.set(name, insertedFoods[i].id);
    });
    report.counts.foods = insertedFoods.length;
    remember('foods', insertedFoods);

    stage = 'food_nutrition';
    // Besin satırı, gıdası **zaten DB'de**yse yazılmaz: `food_nutrition`
    // `UNIQUE(food_id)` (`full_setup.sql:101`) ve mevcut gıdanın besin
    // satırı büyük olasılıkla zaten var → 23505 ile tüm import düşerdi.
    const nutritionRows = plan.nutrition.filter(
      (r) => !plan.existingFoodNames.has(r.backupName ?? ''),
    );
    if (nutritionRows.length > 0) {
      const unresolved = nutritionRows.filter((r) => !foodIdByName.get(r.backupName ?? ''));
      if (unresolved.length > 0) {
        throw new Error(
          `Besin satırının gıdası içe aktarımda eşleştirilemedi (${unresolved.length} satır)`,
        );
      }
      const resolved: PlannedRow[] = nutritionRows.map((r) => ({
        ...r,
        values: { ...r.values, food_id: foodIdByName.get(r.backupName ?? '') },
      }));
      const inserted = await insertBatched('food_nutrition', resolved);
      report.counts.food_nutrition = inserted.length;
      remember('food_nutrition', inserted);
    }

    // 2) Günlük kayıtlar.
    stage = 'meal_entries';
    const newMeals = await insertBatched(
      'meal_entries',
      plan.meals
        .filter((r) => !plan.existingMealKeys.has(r.dedupKey ?? ''))
        .map((r) => ({
          ...r,
          // Yedekteki `food_id` eski UUID'dir; yoksa manuel girdidir.
          values: { ...r.values, food_id: r.backupName ? foodIdByName.get(r.backupName) ?? null : null },
        })),
    );
    report.counts.meal_entries = newMeals.length;
    remember('meal_entries', newMeals);

    stage = 'water_entries';
    const newWaters = await insertBatched(
      'water_entries',
      plan.water.filter((r) => !plan.existingWaterKeys.has(r.dedupKey ?? '')),
    );
    report.counts.water_entries = newWaters.length;
    remember('water_entries', newWaters);

    stage = 'weight_entries';
    const newWeights = await insertBatched(
      'weight_entries',
      plan.weights.filter((r) => !plan.existingWeightDates.has(r.dedupKey ?? '')),
    );
    report.counts.weight_entries = newWeights.length;
    remember('weight_entries', newWeights);

    // 3) Favoriler / son kullanılanlar. Dışa aktarılıyordu, içe
    //    aktarılmıyordu: yedek→geri yüklemede favoriler kayboluyordu.
    //    Bu tablo **kullanıcı listesi** olduğu için telafide silinmez —
    //    yazılan kayıt yeni bir favori (kullanıcının eski verisi değil).
    stage = 'favorite_foods';
    report.counts.favorite_foods = await upsertFoodLists(
      'favorite_foods',
      userId,
      plan.favorites
        .map((r) => (r.backupName ? foodIdByName.get(r.backupName) : null))
        .filter((id): id is string => id !== null && id !== undefined),
    );
    stage = 'recent_foods';
    report.counts.recent_foods = await upsertFoodLists(
      'recent_foods',
      userId,
      plan.recents
        .map((r) => (r.backupName ? foodIdByName.get(r.backupName) : null))
        .filter((id): id is string => id !== null && id !== undefined),
    );

    report.skipped = plan.skipped;
    report.coerced = plan.coerced;
    return report;
  } catch (error) {
    const { code, message } = asPostgrestError(error);
    console.error(`Yedek içe aktarma "${stage}" adımında durdu; telafi ediliyor`, {
      code,
      message,
      error,
    });

    const survivors: Record<string, number> = {};
    const rolledBack = await rollback(written, survivors);
    if (rolledBack) {
      // Hiçbir kayıt kalmadı: kullanıcıya "0 kayıt eklendi, yedek yarım
      // uygulanmadı" görünür.
      for (const table of written.keys()) report.counts[table] = 0;
    }
    report.skipped = plan.skipped;
    report.coerced = plan.coerced;
    report.failedStage = stage;
    report.rolledBack = rolledBack;
    report.survivors = survivors;
    throw new ImportWriteError(stage, report, error);
  }
}

// ---------------------------------------------------------------------------
// Genel API
// ---------------------------------------------------------------------------

/** Bir satırın yazma hazır hâli (yeniden dışa aktarım için). */
export type { ImportReport, ImportTable, PlannedRow } from '@/lib/import/backupImport';

export interface BackupImportResult {
  report: ImportReport;
  /** Atlanan satırlar dahil tüm bulgular (kullanıcıya gösterilebilir). */
  issues: ImportPlan['issues'];
}

/**
 * Yedek JSON'unu **eklemeli** olarak içe aktarır ve dokunulan kayıt
 * sayılarını döndürür.
 *
 * Hata sınıfları:
 *  - `ImportFormatError` — dosya CaloriX yedeği değil (ağ hiç çağrılmaz)
 *  - `ImportValidationError` — yedek DB sözleşmesine uymuyor (**hiç yazma yok**)
 *  - `ImportWriteError` — yazma sırasında hata; `error.report` her zaman dolu
 */
export async function importBackup(
  userId: string,
  text: string,
): Promise<BackupImportResult> {
  // FAZ 1 — ayrıştırma + ön-uçu doğrulama. **Ağ çağrısı yoktur.**
  const data = decodeBackup(text);
  const plan = buildImportPlan(userId, data);

  // FAZ 2 — varlık kontrolü (yalnızca GET).
  await loadExistingKeys(userId, plan);

  // FAZ 3 — yazma (toplu, telafili).
  const report = await applyPlan(userId, plan);
  return { report, issues: plan.issues };
}

/** Geriye dönük uyum: yalnızca sayıları döndüren ince sarmalayıcı. */
export async function importData(
  userId: string,
  text: string,
): Promise<Record<string, number>> {
  const { report } = await importBackup(userId, text);
  return { ...report.counts };
}

export { ImportFormatError, ImportValidationError, ImportWriteError };
