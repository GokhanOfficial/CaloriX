/**
 * Yedek **içe aktarımının saf katmanı**: ayrıştırma, DB sözleşmesine göre
 * doğrulama, yazma planı ve telafi hesabı.
 *
 * ## Neden ayrı dosya
 *
 * `useDataExport.ts` bu dosyayı **yalnızca** çağırır; burada **hiçbir ağ
 * çağrısı ve yan etki yoktur**. Bu, "doğrulama hatasında hiçbir kayıt
 * yazılmadığı" davranışının testte kanıtlanabilmesini sağlar (ağ olmadığı
 * için kanıtlanacak yan etki de yoktur).
 *
 * Bu, Flutter tarafındaki `data_transfer_import.dart` +
 * `data_transfer_repository.dart` çiftinin TypeScript karşılığıdır; DB
 * sözleşmesi (CHECK kısıtları, enum değerleri, UNIQUE) **birebir aynıdır**:
 *   - `supabase/full_setup.sql:616-620` — `meal_entries_amount_positive`,
 *     `water_entries_amount_positive`, `weight_entries_weight_range`
 *   - `supabase/full_setup.sql:106-152` — kolon tipleri ve `NOT NULL`'lar
 *   - `supabase/full_setup.sql:101` — `food_nutrition UNIQUE(food_id)`
 *
 * ## Doğrulama sözleşmesi
 *
 * | Durum | Sonuç |
 * |---|---|
 * | Dosya CaloriX yedeği değil (JSON bozuk / `version`–`exportedAt` yok) | `ImportFormatError` |
 * | Satır DB'nin **kabul etmeyeceği** değer yazıyor (aralık dışı miktar/kilo, sayı olmayan zorunlu sayı) | `ImportValidationError` — **hiçbir istek atılmaz** |
 * | Satır gereksiz (isimsiz gıda, anahtarsız öğün, `deleted_at` dolu, yinelenen dedup anahtarı) | atlanır, `skipped` + `ImportIssue` |
 * | Alan güvenli varsayılana çekilebiliyor (geçersiz `meal_type`→`snack`, `source`→`manual`, küsüratlı `amount_ml`→yuvarlama) | yazılır, `coerced` artar |
 * | Yazma hatası | çağıran telafi eder, `ImportReport` **her zaman** dolu |
 */

// ---------------------------------------------------------------------------
// Hata sınıfları
// ---------------------------------------------------------------------------

/** Tek bir satır hakkında bulgu. */
export interface ImportIssue {
  table: string;
  /** Yedekteki satır `id`'si (yoksa `null`). */
  rowId: string | null;
  field: string;
  message: string;
  /** `true` → içe aktarma hiçbir şey yazmadan durur. */
  isFatal: boolean;
}

/** Dosya CaloriX yedeği değil. */
export class ImportFormatError extends Error {
  override name = 'ImportFormatError';
  constructor(message = 'Geçersiz CaloriX yedek dosyası') {
    super(message);
  }
}

/**
 * Ön-uçu doğrulaması yedeği reddetti — **hiçbir istek atılmadı**.
 *
 * `foods` dahil hiçbir tabloya yazılmadan durulur; kullanıcı yedeğini
 * düzeltip tekrar deneyebilir, yarım veri oluşmaz.
 */
export class ImportValidationError extends Error {
  override name = 'ImportValidationError';
  /** Yalnızca ölümcül ihlaller. */
  readonly issues: ImportIssue[];
  /** Atlanan (ölümcül olmayan) bulgular dahil toplam. */
  readonly totalIssues: number;

  constructor(issues: ImportIssue[], totalIssues: number = issues.length) {
    super('Yedek doğrulanamadı');
    this.issues = issues;
    this.totalIssues = totalIssues;
  }

  /** Kullanıcıya gösterilebilecek tek satır (dosya yolu/kolon adı taşımaz). */
  get summary(): string {
    const first = this.issues[0];
    const more = this.issues.length - 1;
    const extra = more > 0 ? ` (+${more} sorun daha)` : '';
    return `Yedek doğrulanamadı: ${first.message}${extra}`;
  }
}

/** Yazma sırasında hata — taşıdığı rapor sayesinde üç soru da yanıtlanır. */
export class ImportWriteError extends Error {
  override name = 'ImportWriteError';
  /** Hatanın olduğu adım. */
  readonly stage: string;
  /** O ana kadar yazılanların dökümü + telafi durumu. */
  readonly report: ImportReport;
  /** Altta yatan hata. */
  readonly cause: unknown;

  constructor(stage: string, report: ImportReport, cause: unknown) {
    super(`İçe aktarma "${stage}" adımında durdu`);
    this.stage = stage;
    this.report = report;
    this.cause = cause;
  }
}

// ---------------------------------------------------------------------------
// DB sözleşmesi sabitleri
// ---------------------------------------------------------------------------

/** `food_source` ENUM (`20260822000000_remove_barcode.sql`). */
export const FOOD_SOURCE_VALUES = ['photo', 'text', 'manual'] as const;

/** `meal_type` ENUM + DB CHECK (`full_setup.sql:11`). */
export const MEAL_TYPE_VALUES = ['breakfast', 'lunch', 'dinner', 'snack'] as const;

/** `meal_entries.amount_g_ml` CHECK üst sınırı (`full_setup.sql:616`). */
export const MAX_AMOUNT_G_ML = 10000;
/** `water_entries.amount_ml` CHECK üst sınırı (`full_setup.sql:618`). */
export const MAX_AMOUNT_ML = 10000;
/** `weight_entries.weight_kg` CHECK üst sınırı (`full_setup.sql:620`). */
export const MAX_WEIGHT_KG = 1000;

/**
 * İçe aktarımda tek HTTP isteğinde gönderilecek en fazla satır.
 *
 * PostgREST çok satırlı `POST`'u **tek SQL deyimi** olarak gönderir; bir
 * dilim ya tamamen yazılır ya hiç. Sınır Postgres parametre tavanı
 * (65535) ile belirlenir: en geniş tablo `meal_entries` = 14 kolon →
 * 500 × 14 = 7000 (%11).
 */
export const IMPORT_BATCH_SIZE = 500;

/**
 * `in` filtresi dilim boyutu.
 *
 * PostgREST'in pratik URL tavanı ~8 KB'dir; 36 haneli bir UUID + 2 tırnak +
 * virgül = 39 bayt olduğundan 8 KB'de ~210 kayıt sığar. 100 güvenli (en kötü
 * ~6 KB).
 */
export const IN_FILTER_CHUNK_SIZE = 100;

/**
 * Sıra bağımlılık sırasıdır; telafi bu sıranın **tersinde** yürür.
 *
 * `favorite_foods`/`recent_foods` `food_id` FK'si nedeniyle `foods`'ten
 * sonra gelir; ikisi de `UNIQUE(user_id, food_id)` (`full_setup.sql:193/203`)
 * olduğu için `upsert` ile yazılır (aynı gıda iki kez eklenmez).
 */
export const IMPORT_TABLES = [
  'foods',
  'food_nutrition',
  'meal_entries',
  'water_entries',
  'weight_entries',
  'favorite_foods',
  'recent_foods',
] as const;

export type ImportTable = (typeof IMPORT_TABLES)[number];

/** Çok satırlı `POST`'ta gönderilecek **sabit** kolon kümesi (`PGRST102`). */
const INSERT_COLUMNS: Record<ImportTable, readonly string[]> = {
  foods: [
    'name',
    'brand',
    'serving_size_g',
    'serving_description',
    'source',
    'image_url',
    'created_by',
  ],
  food_nutrition: [
    'food_id',
    'per_100_g_ml',
    'kcal',
    'protein_g',
    'carbs_g',
    'fat_g',
    'fiber_g',
    'sugar_g',
    'salt_g',
    'saturated_fat_g',
    'nova_score',
    'nutri_score',
  ],
  meal_entries: [
    'user_id',
    'entry_date',
    'meal_type',
    'food_id',
    'custom_name',
    'amount_g_ml',
    'calculated_kcal',
    'calculated_protein',
    'calculated_carbs',
    'calculated_fat',
    'note',
    'photo_url',
    'source',
    'created_at',
  ],
  water_entries: ['user_id', 'entry_date', 'entry_time', 'amount_ml', 'created_at'],
  weight_entries: ['user_id', 'entry_date', 'weight_kg', 'note', 'created_at'],
  favorite_foods: ['food_id', 'created_at'],
  recent_foods: ['food_id', 'last_used_at', 'use_count'],
};

// ---------------------------------------------------------------------------
// Plan tipleri
// ---------------------------------------------------------------------------

/** Bir satırın yazma hazır hâli. */
export interface PlannedRow {
  /** DB'ye gönderilecek kolon kümesi (sabit, tabloya göre). */
  values: Record<string, unknown>;
  /** Yedekteki `id` — hata raporlarında kullanıcıya gösterilir. */
  backupId: string | null;
  /** `foods` için gıda adı; diğer tablolarda **referans verilen gıdanın adı**. */
  backupName: string | null;
  /** Varlık kontrolü anahtarı. */
  dedupKey: string | null;
}

/** Ön-uçu sonucu: hiçbir istek atılmadan hazırlanmış yazma planı. */
export interface ImportPlan {
  foods: PlannedRow[];
  nutrition: PlannedRow[];
  meals: PlannedRow[];
  water: PlannedRow[];
  weights: PlannedRow[];
  /** `favorite_foods` — yedekte dışa aktarılıyordu, içe aktarılmıyordu. */
  favorites: PlannedRow[];
  /** `recent_foods` — aynı tutarsızlık. */
  recents: PlannedRow[];
  /** Varlık kontrolü `in` listeleri (benzersiz). */
  foodNames: string[];
  /** Favori/son kullanılan gıdaların **yedeğin** `food_id`'leri (eşleme için). */
  favoriteBackupIds: string[];
  recentBackupIds: string[];
  mealDates: string[];
  waterInstants: string[];
  weightDates: string[];
  /** DB'de zaten var olanlar (faz 2'de doldurulur) → yeniden yazılmaz. */
  existingFoodNames: Set<string>;
  existingMealKeys: Set<string>;
  existingWaterKeys: Set<string>;
  existingWeightDates: Set<string>;
  /** Yedeğin `id`'si → gıda adı. */
  foodNameByBackupId: Map<string, string>;
  /** DB'de var olan gıda adı → `id`. İlk eşleşme kazanır. */
  existingFoodIds: Map<string, string>;
  /** Yedeğin `foods` listesinde olmayan ama `food_nutrition`'ta referans verilen gıda adı → `id`. */
  externalFoodIds: Map<string, string>;
  skipped: Record<string, number>;
  coerced: Record<string, number>;
  issues: ImportIssue[];
}

export function emptyCounts(): Record<ImportTable, number> {
  return {
    foods: 0,
    food_nutrition: 0,
    meal_entries: 0,
    water_entries: 0,
    weight_entries: 0,
    favorite_foods: 0,
    recent_foods: 0,
  };
}

/** İçe aktarmanın görünür sonucu. Hata hâlinde de `counts` doludur. */
export interface ImportReport {
  counts: Record<ImportTable, number>;
  skipped: Record<string, number>;
  coerced: Record<string, number>;
  /** Hatanın olduğu adım; başarılıysa `null`. */
  failedStage: ImportTable | null;
  /** Telafi başarılı mı. `null` → hata olmadı. */
  rolledBack: boolean | null;
  /** Telafi başarısız olduğunda yazılı kalan satırlar (tablo → sayı). */
  survivors: Record<string, number>;
}

export function emptyReport(): ImportReport {
  return {
    counts: emptyCounts(),
    skipped: {},
    coerced: {},
    failedStage: null,
    rolledBack: null,
    survivors: {},
  };
}

// ---------------------------------------------------------------------------
// Saf yardımcılar
// ---------------------------------------------------------------------------

/**
 * ISO zaman damgasını **yerel** takvim tarihine (`yyyy-MM-dd`) çevirir.
 * `toISOString().split('T')[0]` UTC tarihini verir; UTC+03:00'te gece 00:00
 * civarı yapılan kayıtlar "dün" olarak etiketleniyordu.
 */
export function localDateFromIso(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** Yedeğin `entry_date` alanından `yyyy-MM-dd` üretir; okunamazsa `null`. */
export function dateString(value: unknown): string | null {
  if (typeof value === 'string') {
    const t = value.trim();
    if (t.length < 8) return null;
    const parsed = new Date(t);
    if (Number.isNaN(parsed.getTime())) return null;
    return localDateFromIso(parsed.toISOString());
  }
  return null;
}

/** Damga → UTC epoch **mikrosaniye** (dedup anahtarı; `+00:00` ↔ `Z` eşit). */
export function epochMicros(value: unknown): number | null {
  if (typeof value !== 'string') return null;
  const t = value.trim();
  if (!t) return null;
  const parsed = new Date(t);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed.getTime() * 1000;
}

/** Su kaydının çözümlenmiş zaman damgası. */
export interface WaterInstant {
  micros: number;
  /** DB'ye yazılacak ISO-8601 damga (UTC). */
  iso: string;
  /**
   * `entry_date` (`yyyy-MM-dd`). `entry_date` okunabildiyse yedeğin
   * **kendi** günü (yerel ayrıştırma ile), okunamadıysa damganın **UTC**
   * günü — bkz. `utcDateFromMicros`.
   */
  day: string;
}

/**
 * UTC damga → `yyyy-MM-dd`.
 *
 * **Bu kasıtlı olarak UTC'dir** (Flutter `formatUtcDateFromMicros` ile
 * birebir). Yalnız `entry_date` **hiç** okunamıyorsa kullanılır; amaç
 * "hangi güne ait?" sorusuna **verinin kendi saat diliminde** cevap
 * vermektir, yoksa içe aktarma sırasında bulunulan ülkenin günüyle
 * karıştırıp kaydı yanlış güne yazmaktır. Örnek: kullanıcı yedek içe
 * aktarırken `entry_time = 2026-01-01T22:00Z`'yi Türkiye'de yüklüyor →
 * yerel 1 Ocak 01:00 → yerel gün **1 Ocak**. Bu fonksiyon yalnız
 * `entry_date` yoksa devreye girer ve bu durumda kaydın **kendi** günü
 * (UTC) en az veri kaybı yaratır.
 *
 * NOT: `toISOString().slice(0, 10)` deseni `lib/dates.ts`teki
 * `formatLocalDate`in **kötü** karşılığıdır ve normalde kullanılmaz —
 * burada kapsamı öyle daraltılmıştır ki aynı sonuç zorunludur.
 */
function utcDateFromMicros(micros: number): string {
  return new Date(micros / 1000).toISOString().slice(0, 10);
}

/**
 * Su kaydının damgası + günü.
 *
 * `entry_time` yoksa `entry_date`'in gün başlangıcı türetilir ve bu
 * türetme `coerced` sayacıyla **kullanıcıya bildirilir** (sessiz veri
 * kaybı olmaz).
 */
export function waterInstant(
  row: Record<string, unknown>,
  coerced: Record<string, number>,
): WaterInstant | null {
  const micros = epochMicros(row.entry_time);
  const day = dateString(row.entry_date);
  if (micros === null) {
    if (day === null) return null;
    count(coerced, 'water_entries.entry_time');
    const start = Date.parse(`${day}T00:00:00Z`);
    if (Number.isNaN(start)) return null;
    return { micros: start * 1000, iso: new Date(start).toISOString(), day };
  }
  return { micros, iso: new Date(micros / 1000).toISOString(), day: day ?? utcDateFromMicros(micros) };
}

/**
 * Yedeğin `created_at` damgasını taşır (toplu yazım "ekleme sırası"
 * korumasını bozmaz).
 *
 * Gerçekçi olmayan damgalar (2000 öncesi, gelecek) yok sayılır → `null`
 * gönderilir ve PostgREST alanı gövdeden düşürür, DB `now()` devreye girer.
 */
export function createdAt(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const parsed = new Date(value.trim());
  if (Number.isNaN(parsed.getTime())) return null;
  const year = Number(new Date(parsed.getTime()).getUTCFullYear());
  if (year < 2000) return null;
  if (parsed.getTime() > Date.now() + 24 * 60 * 60 * 1000) return null;
  return parsed.toISOString();
}

export function chunk<T>(values: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < values.length; i += size) out.push(values.slice(i, i + size));
  return out;
}

export function inFilterChunks<T>(values: readonly T[]): T[][] {
  return chunk(values, IN_FILTER_CHUNK_SIZE);
}

function count(counter: Record<string, number>, key: string): void {
  counter[key] = (counter[key] ?? 0) + 1;
}

function positiveInt(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value) && value > 0) return value;
  return null;
}

/**
 * Favori/son-kullanılan satırın yedekteki `food_id`'si.
 *
 * `food_id` gıdası yedekte yoksa `null` döner (satır `skip` ile atlanır):
 * `favorite_foods.food_id` / `recent_foods.food_id` `NOT NULL` + FK'dir
 * (`full_setup.sql:187/197`), yani yedekteki eski UUID'yi doğrudan
 * yazmak 23503/23502 ile düşürür veya — daha kötüsü — yedek `id`sini
 * `food_id` sanan bir kod sessizce yanlış gıdayı favori yapar.
 */
function backupFoodId(
  row: Record<string, unknown>,
  table: string,
  field: string,
  skip: (table: string, field: string, message: string, rowId: unknown) => void,
): string | null {
  const id = row.food_id === undefined || row.food_id === null ? null : String(row.food_id);
  if (id === null || id === '') {
    skip(table, field, 'Kaydın gıda bağlantısı yok', row.id);
    return null;
  }
  return id;
}

function str(value: unknown): string | null {
  if (typeof value === 'string') {
    const t = value.trim();
    return t.length === 0 ? null : t;
  }
  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function rowsOf(raw: unknown): Record<string, unknown>[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(isRecord);
}

/** Yumuşak silinmiş satır mı? */
export function isDeleted(row: Record<string, unknown>): boolean {
  const v = row.deleted_at;
  if (v === null || v === undefined) return false;
  if (typeof v === 'string') return v.length > 0;
  return true;
}

function liveRowsOf(raw: unknown): Record<string, unknown>[] {
  return rowsOf(raw).filter((row) => !isDeleted(row));
}

/** Öğün dedup anahtarı (`tarih|isim|tip`). */
export function mealKey(date: string, customName: unknown, type: unknown): string | null {
  if (!type || typeof type !== 'string') return null;
  const name = typeof customName === 'string' ? customName : '';
  return `${date}|${name}|${type}`;
}

// --- DB sözleşmesi denetim yardımcıları ------------------------------------

/**
 * DB'nin `NUMERIC`/CHECK sözleşmesine **girmeyen** zorunlu sayısal alan.
 *
 * Ölümcül ihlal üretir: geçersizde `0` yazmak DB 400'ü verir ve import
 * **tüm öğünler yazıldıktan sonra** ölür (kısmi veri + kullanıcıya yalan).
 */
function requireRange(
  value: unknown,
  field: string,
  table: string,
  rowId: string | null,
  issues: ImportIssue[],
  min: number,
  max: number,
): number {
  if (typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max) {
    return value;
  }
  issues.push({
    table,
    rowId,
    field,
    message: `${field} DB sözleşmesinin dışında (${min} < değer <= ${max} olmalı)`,
    isFatal: true,
  });
  return min;
}

/** `NOT NULL numeric` alan: sayı değilse ölümcül (`0`'a çevirmek yanlış veriydi). */
function requireNumber(
  value: unknown,
  field: string,
  table: string,
  rowId: string | null,
  issues: ImportIssue[],
): number {
  if (typeof value === 'number' && Number.isFinite(value) && value >= 0) return value;
  issues.push({
    table,
    rowId,
    field,
    message: `${field} sayı değil (DB NOT NULL numeric)`,
    isFatal: true,
  });
  return 0;
}

function positiveNum(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value) && value > 0) return value;
  return null;
}

function nonNegativeNum(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value) && value >= 0) return value;
  return null;
}

/** ENUM/CHECK alanı — geçersizse DB varsayılanına çekilir ve **sayılır**. */
function enumValue(
  value: unknown,
  allowed: readonly string[],
  fallback: string,
  field: string,
  table: string,
  rowId: string | null,
  issues: ImportIssue[],
  coerced: Record<string, number>,
): string {
  if (typeof value === 'string' && allowed.includes(value)) return value;
  count(coerced, `${table}.${field}`);
  return fallback;
}

// ---------------------------------------------------------------------------
// FAZ 1 — ayrıştırma + doğrulama (ağ yok)
// ---------------------------------------------------------------------------

/**
 * Yedeği ayrıştırır ve biçim sözleşmesini doğrular.
 * `ImportFormatError` fırlatır → **ağ hiç çağrılmaz**.
 */
export function decodeBackup(text: string): Record<string, unknown> {
  let decoded: unknown;
  try {
    decoded = JSON.parse(text);
  } catch {
    throw new ImportFormatError('Geçersiz CaloriX yedek dosyası (JSON okunamadı)');
  }
  if (!isRecord(decoded) || !decoded.version || !decoded.exportedAt) {
    throw new ImportFormatError('Geçersiz CaloriX yedek dosyası');
  }
  return decoded;
}

/**
 * Yedek satırlarını DB sözleşmesine göre **yazmaya hazır** hâle getirir.
 *
 * Saf fonksiyon: `ImportValidationError` fırlattığında istemciye hiç
 * dokunulmamıştır. `userId` yedekteki `user_id`/`created_by` **yok sayılır**
 * (başka birinin yedeği kullanıcıya verilse bile kayıtlar doğru sahiplikle
 * yazılır).
 */
export function buildImportPlan(userId: string, data: Record<string, unknown>): ImportPlan {
  const issues: ImportIssue[] = [];
  const coerced: Record<string, number> = {};
  const plan: ImportPlan = {
    foods: [],
    nutrition: [],
    meals: [],
    water: [],
    weights: [],
    favorites: [],
    recents: [],
    foodNames: [],
    favoriteBackupIds: [],
    recentBackupIds: [],
    mealDates: [],
    waterInstants: [],
    weightDates: [],
    existingFoodNames: new Set(),
    existingMealKeys: new Set(),
    existingWaterKeys: new Set(),
    existingWeightDates: new Set(),
    foodNameByBackupId: new Map(),
    existingFoodIds: new Map(),
    externalFoodIds: new Map(),
    skipped: {},
    coerced,
    issues,
  };

  const skip = (table: string, field: string, message: string, rowId: unknown) => {
    plan.skipped[table] = (plan.skipped[table] ?? 0) + 1;
    issues.push({
      table,
      rowId: rowId === undefined || rowId === null ? null : String(rowId),
      field,
      message,
      isFatal: false,
    });
  };

  /**
   * Varlık kontrolü `in` listelerine **benzersiz** değer ekler.
   *
   * 2000 öğünlük bir yedekte gün başına 4 öğün vardır: liste benzersiz
   * tutulmazsa aynı gün 4 kez eklenir ve `in` sorguları gereksiz 4 kat
   * URL uzunluğuna çıkar (8 KB tavanı dilim sayısını 4× artırır).
   */
  const pushUnique = (list: string[], seen: Set<string>, value: string) => {
    if (seen.has(value)) return;
    seen.add(value);
    list.push(value);
  };
  const seenDates = new Set<string>();
  const seenWaterInstants = new Set<string>();

  // 1) foods — dedup: `name` (birebir, büyük/küçük harf duyarsız değil:
  //    DB'deki ad neyse aynısı eşleşir, `useDataExport` ile aynı davranış).
  const seenFoodNames = new Set<string>();
  for (const food of rowsOf(data.foods)) {
    const name = str(food.name);
    if (name === null) {
      skip('foods', 'name', 'Gıdanın adı boş', food.id);
      continue;
    }
    const oldId = food.id === undefined || food.id === null ? null : String(food.id);
    if (oldId === null || oldId === '') {
      skip('foods', 'id', 'Gıdanın kimliği yok — öğünlerle eşleştirilemez', null);
      continue;
    }
    if (seenFoodNames.has(name)) {
      skip('foods', 'name', 'Yedekte aynı adı taşıyan ikinci gıda (tekrar sayıldı)', oldId);
      continue;
    }
    seenFoodNames.add(name);
    plan.foods.push({
      values: foodRow(food, userId, name, issues, coerced),
      backupId: oldId,
      backupName: name,
      dedupKey: name,
    });
    plan.foodNames.push(name);
    plan.foodNameByBackupId.set(oldId, name);
  }

  // 2) food_nutrition — `food_id` içe aktarımda **yeni** gıda id'sidir.
  //    `UNIQUE(food_id)` (`full_setup.sql:101`): ikinci satır 23505 ile düşürür.
  const seenNutrition = new Set<string>();
  for (const n of rowsOf(data.food_nutrition)) {
    const oldFoodId =
      n.food_id === undefined || n.food_id === null ? null : String(n.food_id);
    if (oldFoodId === null || oldFoodId === '') {
      skip('food_nutrition', 'food_id', 'Besin satırının gıda bağlantısı yok', null);
      continue;
    }
    const name = plan.foodNameByBackupId.get(oldFoodId);
    if (name === undefined) {
      // Yedeğin `foods` listesinde karşılığı yok (elle düzenlenmiş yedek).
      skip('food_nutrition', 'food_id', 'Besin satırının gıdası yedekte yok', oldFoodId);
      continue;
    }
    if (seenNutrition.has(oldFoodId)) {
      skip('food_nutrition', 'food_id', 'Aynı gıda için ikinci besin satırı (UNIQUE food_id)', oldFoodId);
      continue;
    }
    seenNutrition.add(oldFoodId);
    plan.nutrition.push({
      values: nutritionRow(n, issues, coerced),
      backupId: oldFoodId,
      backupName: name,
      dedupKey: null,
    });
  }

  // 3) meal_entries — dedup: `entry_date` + `custom_name` + `meal_type`.
  //    `meal_entries` üzerinde bu kombinasyona UNIQUE yoktur; yumuşak
  //    silinmiş satırlar varlık kontrolüne de girmemeli (aksi hâlde DB'deki
  //    silinmiş satır canlı satırın yeniden eklenmesini engeller).
  const seenMealKeys = new Set<string>();
  for (const m of liveRowsOf(data.meal_entries)) {
    const day = dateString(m.entry_date);
    if (day === null) {
      // Tarih çözümlenemiyorsa ölümcül: öğünün nereye yazılacağı bilinmiyor.
      issues.push({
        table: 'meal_entries',
        rowId: m.id === undefined || m.id === null ? null : String(m.id),
        field: 'entry_date',
        message: 'Öğünün tarihi okunamadı (beklenen: yyyy-MM-dd)',
        isFatal: true,
      });
      continue;
    }
    const key = mealKey(day, m.custom_name, m.meal_type);
    if (key === null) {
      skip('meal_entries', 'meal_type', 'Öğünün tipi eksik — nereye yazılacağı bilinmiyor', m.id);
      continue;
    }
    if (seenMealKeys.has(key)) {
      skip('meal_entries', 'entry_date', 'Yedekte aynı gün/öğün/yemek için ikinci kayıt (tekrar sayıldı)', m.id);
      continue;
    }
    seenMealKeys.add(key);
    pushUnique(plan.mealDates, seenDates, day);
    const foodId = m.food_id === undefined || m.food_id === null ? null : String(m.food_id);
    plan.meals.push({
      values: mealRow(m, userId, day, issues, coerced),
      backupId: m.id === undefined || m.id === null ? null : String(m.id),
      backupName: foodId === null ? null : (plan.foodNameByBackupId.get(foodId) ?? null),
      dedupKey: key,
    });
  }

  // 4) water_entries — dedup: `entry_time` (epoch mikrosaniye).
  const seenWater = new Set<string>();
  for (const w of liveRowsOf(data.water_entries)) {
    const when = waterInstant(w, coerced);
    if (when === null) {
      // `entry_time NOT NULL` ve dedup anahtarı bu damga → zamanı
      // çözümlenemeyen kayıt **ölümcüldür** (sessizce atlanırsa günlük su
      // toplamı eksik kalır ve bildirim gelmez).
      issues.push({
        table: 'water_entries',
        rowId: w.id === undefined || w.id === null ? null : String(w.id),
        field: 'entry_time',
        message: 'Su kaydının zamanı okunamadı (beklenen ISO-8601 damga ve da entry_date)',
        isFatal: true,
      });
      continue;
    }
    const key = String(when.micros);
    if (seenWater.has(key)) {
      skip('water_entries', 'entry_time', 'Yedekte aynı anda ikinci su kaydı (tekrar sayıldı)', w.id);
      continue;
    }
    seenWater.add(key);
    pushUnique(plan.waterInstants, seenWaterInstants, when.iso);
    plan.water.push({
      values: waterRow(w, userId, when, issues, coerced),
      backupId: w.id === undefined || w.id === null ? null : String(w.id),
      backupName: null,
      dedupKey: key,
    });
  }

  // 5) favorite_foods / recent_foods — **yalnızca `food_id` üzerinden**
  //    anlamlı. Yedekteki `id` yeni kullanıcıya ait olmayan eski bir
  //    UUID'dir; `food_id` ise `foods` listesiyle eşleştirilir. Gıdası
  //    yedekte olmayan kayıt atlanır (FK ihlali olmaz), çünkü kullanıcının
  //    **gerçek gıda satırına** bağlanamaz.
  for (const f of rowsOf(data.favorite_foods)) {
    const id = backupFoodId(f, 'favorite_foods', 'food_id', skip);
    if (id === null) continue;
    if (plan.foodNameByBackupId.get(id) === undefined) {
      skip('favorite_foods', 'food_id', 'Favorinin gıdası yedekte yok', id);
      continue;
    }
    plan.favoriteBackupIds.push(id);
    plan.favorites.push({
      values: { food_id: null, created_at: createdAt(f.created_at) },
      backupId: id,
      backupName: plan.foodNameByBackupId.get(id) ?? null,
      dedupKey: id,
    });
  }
  for (const f of rowsOf(data.recent_foods)) {
    const id = backupFoodId(f, 'recent_foods', 'food_id', skip);
    if (id === null) continue;
    if (plan.foodNameByBackupId.get(id) === undefined) {
      skip('recent_foods', 'food_id', 'Son kullanılan gıda yedekte yok', id);
      continue;
    }
    plan.recentBackupIds.push(id);
    plan.recents.push({
      values: {
        food_id: null,
        last_used_at: createdAt(f.last_used_at),
        // `use_count` **bilinçli olarak** DB varsayılanına (1) çekilir.
        // Geri yüklemede kullanıcının "bu gıdayı kaç kez kullandığı"
        // bilgisi kopyalanmaz: yazım `ignoreDuplicates` ile yapılır, yani
        // gıda zaten varsa DB'nin mevcut sayacı korunur. Yedekteki sayı
        // yalnızca **yeni** eklenen gıdalar için anlamlı olurdu ve
        // tutarsız bir geri yükleme üretirdi (mevcut gıdalarda eski,
        // yenilerde yedek değeri). Düzeltme `coerced` ile bildirilir.
        use_count: positiveInt(f.use_count) === 1
          ? 1
          : (count(coerced, 'recent_foods.use_count'), 1),
      },
      backupId: id,
      backupName: plan.foodNameByBackupId.get(id) ?? null,
      dedupKey: id,
    });
  }

  // 6) weight_entries — dedup: `entry_date`.
  const seenWeightDates = new Set<string>();
  for (const w of liveRowsOf(data.weight_entries)) {
    const day = dateString(w.entry_date);
    if (day === null) {
      // `entry_date DATE NOT NULL` ve dedup anahtarı da bu gün → ölümcül.
      issues.push({
        table: 'weight_entries',
        rowId: w.id === undefined || w.id === null ? null : String(w.id),
        field: 'entry_date',
        message: 'Kilo kaydının tarihi okunamadı (beklenen: yyyy-MM-dd)',
        isFatal: true,
      });
      continue;
    }
    if (seenWeightDates.has(day)) {
      skip('weight_entries', 'entry_date', 'Yedekte aynı gün için ikinci kilo kaydı (tekrar sayıldı)', w.id);
      continue;
    }
    seenWeightDates.add(day);
    pushUnique(plan.weightDates, seenDates, day);
    plan.weights.push({
      values: weightRow(w, userId, day, issues, coerced),
      backupId: w.id === undefined || w.id === null ? null : String(w.id),
      backupName: null,
      dedupKey: day,
    });
  }

  // Tek bir ölümcül ihlalde **hiçbir yazma yapılmadan** dur.
  const fatal = issues.filter((i) => i.isFatal);
  if (fatal.length > 0) {
    throw new ImportValidationError(fatal, issues.length);
  }
  return plan;
}

// ---------------------------------------------------------------------------
// Satır dönüştürücüleri (beyaz liste)
// ---------------------------------------------------------------------------

/**
 * `foods` yedeğini beyaz listeler.
 *
 * Kara liste kullanılmaz: yedekteki tanınmayan her kolon PostgREST
 * `PGRST204` ile 400 döndürür ve **tek bozuk alan tüm import'u** düşürür.
 * `verified`/`popularity_count` bilinçli olarak dışarıda: ikisi de sistem
 * tarafından türetilir (`increment_food_popularity` trigger'ı).
 */
function foodRow(
  food: Record<string, unknown>,
  userId: string,
  name: string,
  issues: ImportIssue[],
  coerced: Record<string, number>,
): Record<string, unknown> {
  return {
    name,
    brand: str(food.brand),
    serving_size_g: positiveNum(food.serving_size_g) ?? 100,
    serving_description: str(food.serving_description),
    source: enumValue(
      food.source,
      FOOD_SOURCE_VALUES,
      'manual',
      'source',
      'foods',
      food.id === undefined ? null : String(food.id),
      issues,
      coerced,
    ),
    image_url: str(food.image_url),
    created_by: userId,
  };
}

/**
 * `food_nutrition` yedeğini beyaz listeler.
 *
 * `kcal/protein_g/carbs_g/fat_g` `NOT NULL` olduğu için sayısal olmayan
 * değer `0`'a **çevrilmez** — önce 0'a çevrilip yazılıyor ve sessizce yanlış
 * besin değeri kaydediliyordu. Sayı değilse satır ölümcül ihlalle reddedilir.
 *
 * `nova_score` `smallint` (1..4): aralık dışı değer alan boş bırakılır
 * (nullable) ve sayılır.
 */
function nutritionRow(
  n: Record<string, unknown>,
  issues: ImportIssue[],
  coerced: Record<string, number>,
): Record<string, unknown> {
  const rowId = n.food_id === undefined || n.food_id === null ? null : String(n.food_id);
  const nova = positiveNum(n.nova_score);
  return {
    per_100_g_ml: typeof n.per_100_g_ml === 'boolean' ? n.per_100_g_ml : true,
    kcal: requireNumber(n.kcal, 'kcal', 'food_nutrition', rowId, issues),
    protein_g: requireNumber(n.protein_g, 'protein_g', 'food_nutrition', rowId, issues),
    carbs_g: requireNumber(n.carbs_g, 'carbs_g', 'food_nutrition', rowId, issues),
    fat_g: requireNumber(n.fat_g, 'fat_g', 'food_nutrition', rowId, issues),
    fiber_g: nonNegativeNum(n.fiber_g),
    sugar_g: nonNegativeNum(n.sugar_g),
    salt_g: nonNegativeNum(n.salt_g),
    saturated_fat_g: nonNegativeNum(n.saturated_fat_g),
    nova_score:
      nova !== null && nova >= 1 && nova <= 4
        ? Math.trunc(nova)
        : (count(coerced, 'food_nutrition.nova_score'), null),
    nutri_score: str(n.nutri_score),
  };
}

/**
 * `meal_entries` yedeğini beyaz listeler.
 *
 * `meal_type`/`source` enum alanları: yedek bozuk/eski bir değer taşırsa
 * (`'brunch'`, `'barcode'`) insert CHECK ihlaliyle 400 döner ve **tüm içe
 * aktarma** orada durur. Geçersiz değerler DB varsayılanına çekilir.
 *
 * `created_at` yedeğin damgasıdır: toplu yazımda satır sırası `created_at`'i
 * taşımadığı için tüm öğünler aynı `now()`'u alır ve "ekleme sırası"
 * koruması kaybolur; damga gövdede taşınır.
 */
function mealRow(
  m: Record<string, unknown>,
  userId: string,
  day: string,
  issues: ImportIssue[],
  coerced: Record<string, number>,
): Record<string, unknown> {
  const rowId = m.id === undefined || m.id === null ? null : String(m.id);
  return {
    user_id: userId,
    entry_date: day,
    meal_type: enumValue(
      m.meal_type,
      MEAL_TYPE_VALUES,
      'snack',
      'meal_type',
      'meal_entries',
      rowId,
      issues,
      coerced,
    ),
    food_id: null, // içe aktarımda **yeni** gıda id'siyle doldurulur
    custom_name: str(m.custom_name),
    amount_g_ml: requireRange(
      m.amount_g_ml,
      'amount_g_ml',
      'meal_entries',
      rowId,
      issues,
      0.0001,
      MAX_AMOUNT_G_ML,
    ),
    calculated_kcal: requireRange(
      m.calculated_kcal,
      'calculated_kcal',
      'meal_entries',
      rowId,
      issues,
      0,
      9999999,
    ),
    calculated_protein: requireRange(
      m.calculated_protein,
      'calculated_protein',
      'meal_entries',
      rowId,
      issues,
      0,
      9999999,
    ),
    calculated_carbs: requireRange(
      m.calculated_carbs,
      'calculated_carbs',
      'meal_entries',
      rowId,
      issues,
      0,
      9999999,
    ),
    calculated_fat: requireRange(
      m.calculated_fat,
      'calculated_fat',
      'meal_entries',
      rowId,
      issues,
      0,
      9999999,
    ),
    note: str(m.note),
    photo_url: str(m.photo_url),
    source: enumValue(
      m.source,
      FOOD_SOURCE_VALUES,
      'manual',
      'source',
      'meal_entries',
      rowId,
      issues,
      coerced,
    ),
    created_at: createdAt(m.created_at),
  };
}

/**
 * `water_entries` yedeğini beyaz listeler.
 *
 * `amount_ml` `INTEGER NOT NULL` olduğu için küsüratlı/string değer 400
 * üretir: küsüratlı değer **yuvarlanır** (250.4 → 250), tam sayı olmayan
 * değer ise ölümcül ihlaldir. Geçersizde `0` yazmak
 * `water_entries_amount_positive` CHECK'i tetiklerdi → **mevcut öğünler
 * yazıldıktan sonra** import su adımında ölürdü.
 */
function waterRow(
  w: Record<string, unknown>,
  userId: string,
  when: WaterInstant,
  issues: ImportIssue[],
  coerced: Record<string, number>,
): Record<string, unknown> {
  const rowId = w.id === undefined || w.id === null ? null : String(w.id);
  const raw = w.amount_ml;
  let ml = 0;
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    const rounded = Math.round(raw);
    if (rounded > 0 && rounded <= MAX_AMOUNT_ML) {
      ml = rounded;
      if (rounded !== raw) count(coerced, 'water_entries.amount_ml');
    }
  }
  if (ml === 0) {
    issues.push({
      table: 'water_entries',
      rowId,
      field: 'amount_ml',
      message: `Su miktarı ${MAX_AMOUNT_ML} ml aralığında değil (DB CHECK: amount_ml > 0 AND amount_ml <= ${MAX_AMOUNT_ML})`,
      isFatal: true,
    });
  }
  return {
    user_id: userId,
    entry_date: when.day,
    entry_time: when.iso,
    amount_ml: ml,
    created_at: createdAt(w.created_at),
  };
}

/**
 * `weight_entries` yedeğini beyaz listeler — `weight_kg NUMERIC(5,2) NOT NULL`
 * ve `weight_entries_weight_range` CHECK (`full_setup.sql:620`).
 *
 * Geçersiz kilo için `0` yazmak DB `0 > 0` CHECK'ini reddedip **tüm
 * import'u** düşürürdü (öğünler ve su kayıtları yazılmış hâlde).
 */
function weightRow(
  w: Record<string, unknown>,
  userId: string,
  day: string,
  issues: ImportIssue[],
  _coerced: Record<string, number>,
): Record<string, unknown> {
  const rowId = w.id === undefined || w.id === null ? null : String(w.id);
  return {
    user_id: userId,
    entry_date: day,
    weight_kg: requireRange(w.weight_kg, 'weight_kg', 'weight_entries', rowId, issues, 0.0001, MAX_WEIGHT_KG),
    note: str(w.note),
    created_at: createdAt(w.created_at),
  };
}

// ---------------------------------------------------------------------------
// Gövde hazırlama
// ---------------------------------------------------------------------------

/**
 * `NOT NULL DEFAULT now()` kolonlar.
 *
 * Yazma sırasında `defaultToNull: false` (`Prefer: missing=default`) kullanılır,
 * bu yüzden **anahtarı gövdeden düşürmek** DB'nin `DEFAULT`'ini
 * devreye sokar. `null` göndermek ise `23502 not_null_violation` üretir.
 *
 * Dart istemcisi bunu `null` yazıp PostgREST'in düşürmesine güveniyor;
 * `@supabase/postgrest-js` `defaultToNull: true` **varsayılanı** olduğu için
 * aynı varsayım burada **yanlış** olurdu (bkz. `PostgrestQueryBuilder.ts:205`).
 */
const DEFAULT_IF_OMITTED = new Set([
  'created_at',
  'last_used_at',
  'updated_at',
]);

/** `insert()` çağrısında kullanılacak seçenekler (sözleşme). */
export const INSERT_PREFER_DEFAULTS = { defaultToNull: false } as const;

/**
 * Her satırı tablonun **sabit** kolon kümesine eşitler.
 *
 * PostgREST çok satırlı `POST`'ta anahtar kümelerinin aynı olmasını şart
 * koşar (`PGRST102`); anahtar kümesi **tablodan** gelir, satırdan değil.
 *
 * `null` yazmak istenen kolonlar **yazılır** (Postgres `DEFAULT`'i değil
 * `NULL`'ı alır). Yalnızca `DEFAULT_IF_OMITTED` kolonları, değeri `null`
 * ise gövdeden **düşürülür** — bkz. yukarıdaki gerekçe.
 */
export function uniform(
  rows: readonly PlannedRow[],
  table: ImportTable,
): Record<string, unknown>[] {
  const columns = INSERT_COLUMNS[table];
  return rows.map((r) => {
    const out: Record<string, unknown> = {};
    for (const c of columns) {
      const v = r.values[c] ?? null;
      if (v === null && DEFAULT_IF_OMITTED.has(c)) continue;
      out[c] = v;
    }
    return out;
  });
}
