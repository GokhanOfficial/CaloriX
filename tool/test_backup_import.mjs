#!/usr/bin/env node
/**
 * Yedek içe aktarımı **mantık testleri** (saf katman).
 *
 * ## Neden ayrı bir koşucu
 *
 * `package.json`'da test koşucusu yok (`vite`/`eslint` dışında dev
 * bağımlılığı yok) ve `supabase.yml`/`flutter.yml` CI işleri Node'in
 * **yerleşik** `node:test` + `--experimental-strip-types` yeteneğini
 * kullanır — ek paket indirmeden TypeScript testleri koşar. Aynı
 * mekanizma burada da kullanılır: `npm test` yeni bir bağımlılık
 * getirmez.
 *
 * ## Kapsam
 *
 * `src/lib/import/backupImport.ts` saf bir modüldür (ağ yok, yan etki
 * yok). Bu testler şu sözleşmeleri sabitler:
 *
 *   1. Doğrulama hatasında **hiçbir** yazma yapılmaz (`ImportValidationError`).
 *   2. DB'nin kabul etmeyeceği değer `0`'a **çevrilmez** → ölümcül olur.
 *   3. `deleted_at` dolu satırlar canlanmaz.
 *   4. Dedup anahtarları: öğün `tarih|isim|tip`, su **epoch mikrosaniye**
 *      (`+00:00` ↔ `Z` aynı kayıt), kilo `tarih`, gıda `ad`.
 *   5. Kullanıcı adı yedekten değil oturumdan gelir.
 *   6. `favorite_foods`/`recent_foods` planlanır (dışa aktarılıyordu,
 *      içe aktarılmıyordu).
 *   7. Yazılan gövde `PGRST102` anahtar kümesi sözleşmesine uyar.
 *
 * Kullanım:
 *   npm test                       # bu dosya
 *   npm test -- --verbose          # ayrıntılı test adları
 *   npm run test:web-verify        # mantık testleri + sözleşme denetimi
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  IMPORT_BATCH_SIZE,
  IMPORT_TABLES,
  IN_FILTER_CHUNK_SIZE,
  ImportFormatError,
  ImportValidationError,
  buildImportPlan,
  chunk,
  createdAt,
  dateString,
  decodeBackup,
  epochMicros,
  inFilterChunks,
  isDeleted,
  localDateFromIso,
  mealKey,
  uniform,
  waterInstant,
} from '../src/lib/import/backupImport.ts';

const USER = 'u1';

/** Gerçekçi bir yedek üretir. */
function backup(overrides = {}) {
  return JSON.stringify({
    version: '1.1.0',
    exportedAt: '2026-09-28T00:00:00Z',
    ...overrides,
  });
}

const mealRow = (o = {}) => ({
  id: 'm1',
  user_id: 'başka-kullanıcı',
  entry_date: '2026-08-15',
  meal_type: 'lunch',
  custom_name: 'Tavuk',
  amount_g_ml: 100,
  calculated_kcal: 500,
  calculated_protein: 30,
  calculated_carbs: 40,
  calculated_fat: 10,
  source: 'manual',
  created_at: '2026-08-15T12:00:00Z',
  ...o,
});

// ===========================================================================
// 1) "Önce doğrula, sonra yaz" — doğrulama hatasında HİÇBİR yazma yok
// ===========================================================================

test('biçim hatası: JSON okunamıyor → ImportFormatError', () => {
  assert.throws(() => decodeBackup('bu json değil {{{'), ImportFormatError);
});

test('version/exportedAt eksik → ImportFormatError', () => {
  assert.throws(() => decodeBackup(JSON.stringify({ foods: [] })), ImportFormatError);
  assert.throws(() => decodeBackup(JSON.stringify({ version: '1.1.0' })), ImportFormatError);
  assert.throws(() => decodeBackup(JSON.stringify([1, 2, 3])), ImportFormatError);
});

test('DB kabul etmeyeceği kilo (0) → ImportValidationError', () => {
  // Önce öğünler: eski sürümde bunlar yazılır, kilo 400'ünde import ölür ve
  // kullanıcı yarım veriyle kalırdı.
  assert.throws(
    () =>
      buildImportPlan(
        USER,
        decodeBackup(
          backup({
            meal_entries: [mealRow()],
            weight_entries: [{ id: 'g1', entry_date: '2026-08-15', weight_kg: 0 }],
          }),
        ),
      ),
    ImportValidationError,
  );
});

test('su miktarı 0 / üst sınır dışı → ölümcül (0 yazmak DB 400 üretirdi)', () => {
  for (const bad of [0, -5, 10001, null, 'çok', undefined]) {
    assert.throws(
      () =>
        buildImportPlan(
          USER,
          decodeBackup(
            backup({
              water_entries: [
                { id: 'w1', entry_date: '2026-08-15', entry_time: '2026-08-15T10:00:00Z', amount_ml: bad },
              ],
            }),
          ),
        ),
      ImportValidationError,
      `amount_ml=${JSON.stringify(bad)} ölümcül olmalı`,
    );
  }
});

test('miktar aralık dışı (DB CHECK: > 0 AND <= 10000) → ölümcül', () => {
  for (const bad of [0, -1, 10001]) {
    assert.throws(
      () =>
        buildImportPlan(USER, decodeBackup(backup({ meal_entries: [mealRow({ amount_g_ml: bad })] }))),
      ImportValidationError,
      `amount_g_ml=${bad}`,
    );
  }
});

test('zorunlu sayısal alan string ise ölümcül (0 yazmak SESSİZ YANLIŞ BESİN DEĞERİYDİ)', () => {
  assert.throws(
    () =>
      buildImportPlan(
        USER,
        decodeBackup(
          backup({
            foods: [{ id: 'f1', name: 'X' }],
            food_nutrition: [
              { food_id: 'f1', kcal: 'çok', protein_g: 1, carbs_g: 1, fat_g: 1 },
            ],
          }),
        ),
      ),
    ImportValidationError,
  );
});

test('tüm ölümcül ihlaller raporda; özet ilk sorunu söyler, ayrıntı sızdırmaz', () => {
  try {
    buildImportPlan(
      USER,
      decodeBackup(
        backup({
          meal_entries: [
            mealRow({ id: 'a', amount_g_ml: 0 }),
            mealRow({ id: 'b', entry_date: '2026-08-16', amount_g_ml: -1 }),
            mealRow({ id: 'c', entry_date: '2026-08-17' }),
          ],
        }),
      ),
    );
    assert.fail('ölümcül ihlalde import durmalıydı');
  } catch (e) {
    assert.ok(e instanceof ImportValidationError);
    assert.equal(e.issues.length, 2);
    assert.ok(e.issues.every((i) => i.isFatal));
    assert.deepEqual(
      e.issues.map((i) => i.rowId).sort(),
      ['a', 'b'],
    );
    assert.match(e.summary, /doğrulanamadı/);
    // Kullanıcı metni dosya yolu/kolon adı taşımaz.
    assert.doesNotMatch(e.summary, /home|\/Users/);
  }
});

test('atlanabilir satırlar ölümcül sayılmaz (import devam eder)', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        foods: [
          { id: 'f1', name: '  ' }, // isimsiz → atlanır
          { id: 'f2' }, // isim yok → atlanır
          { id: 'f3', name: 'Salata' },
        ],
        meal_entries: [
          mealRow({ id: 'm1', custom_name: null }),
          // Yumuşak silinmiş → **yeniden EKLENMEZ** (canlanma hatası)
          mealRow({ id: 'm2', entry_date: '2026-08-16', deleted_at: '2026-08-16T10:00:00Z' }),
          // Aynı anahtarlı ikinci kayıt → atlanır
          mealRow({ id: 'm3', custom_name: null }),
        ],
      }),
    ),
  );
  assert.equal(plan.foods.length, 1);
  assert.equal(plan.meals.length, 1);
  assert.equal(plan.skipped.foods, 2);
  assert.equal(plan.skipped.meal_entries, 1);
  // Silinmiş kayıt DB'ye sızmaz: gövdede `deleted_at` **yok**.
  assert.equal(plan.meals[0].values.deleted_at, undefined);
});

// ===========================================================================
// 2) Veri bütünlüğü: yazılan gövde DB sözleşmesine uyar
// ===========================================================================

test('kullanıcı adı yedekten değil oturumdan gelir', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        foods: [{ id: 'f1', name: 'Tavuk' }],
        meal_entries: [mealRow()],
        water_entries: [{ id: 'w1', entry_date: '2026-08-15', entry_time: '2026-08-15T10:00:00Z', amount_ml: 250 }],
        weight_entries: [{ id: 'g1', entry_date: '2026-08-15', weight_kg: 80 }],
      }),
    ),
  );
  assert.equal(plan.meals[0].values.user_id, USER);
  assert.equal(plan.water[0].values.user_id, USER);
  assert.equal(plan.weights[0].values.user_id, USER);
  assert.equal(plan.foods[0].values.created_by, USER);
});

test('foods: verified/popularity_count/id yedekten kopyalanmaz', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        foods: [
          { id: 'f1', name: 'Ev yapımı köfte', verified: true, popularity_count: 9999, barcode: '8690' },
        ],
      }),
    ),
  );
  const row = plan.foods[0].values;
  for (const banned of ['id', 'verified', 'popularity_count', 'barcode', 'created_by_last']) {
    assert.equal(row[banned], undefined, banned);
  }
  assert.equal(row.name, 'Ev yapımı köfte');
});

test('geçersiz enum değerleri DB varsayılanına çekilir ve SAYILIR', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        foods: [{ id: 'f1', name: 'A', source: 'barcode' }],
        meal_entries: [mealRow({ meal_type: 'brunch' }), mealRow({ id: 'm2', entry_date: '2026-08-16', source: 'barcode' })],
      }),
    ),
  );
  assert.equal(plan.foods[0].values.source, 'manual');
  assert.equal(plan.meals[0].values.meal_type, 'snack');
  assert.equal(plan.meals[1].values.source, 'manual');
  assert.equal(plan.coerced['meal_entries.meal_type'], 1);
  assert.equal(plan.coerced['meal_entries.source'], 1);
  assert.equal(plan.coerced['foods.source'], 1);
});

test('küsüratlı su miktarı yuvarlanır ve SAYILIR (DB 400 vermesin)', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        water_entries: [
          { id: 'w1', entry_date: '2026-08-15', entry_time: '2026-08-15T10:00:00Z', amount_ml: 250.6 },
        ],
      }),
    ),
  );
  assert.equal(plan.water[0].values.amount_ml, 251);
  assert.equal(Number.isInteger(plan.water[0].values.amount_ml), true);
  assert.equal(plan.coerced['water_entries.amount_ml'], 1);
});

test('created_at yedeğin damgasıyla taşınır (toplu yazım sırayı korumaz)', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        meal_entries: [
          mealRow({ id: 'a', created_at: '2026-08-15T12:00:00Z' }),
          mealRow({ id: 'b', entry_date: '2026-08-16', created_at: '2026-08-16T12:00:00Z' }),
        ],
      }),
    ),
  );
  const stamps = new Set(plan.meals.map((m) => m.values.created_at));
  assert.equal(stamps.size, 2, 'her öğün kendi damgasını taşır');
});

test('created_at gerçekçi değilse null (PostgREST düşürür → DB now())', () => {
  assert.equal(createdAt('1999-01-01T00:00:00Z'), null, '2000 öncesi');
  assert.equal(createdAt('bozuk'), null, 'bozuk string');
  assert.equal(createdAt(new Date(Date.now() + 400 * 864e5).toISOString()), null, 'gelecek');
  assert.equal(createdAt('2026-08-15T12:00:00Z'), '2026-08-15T12:00:00.000Z', 'geçerli');
});

test('eski food_id yedeğin UUID\'si olarak yazılmaz (yeni gıda id\'si doldurulur)', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        foods: [{ id: 'eski-id', name: 'Tavuk' }],
        meal_entries: [mealRow({ food_id: 'eski-id' })],
      }),
    ),
  );
  assert.equal(plan.meals[0].backupName, 'Tavuk', 'ad üzerinden eşleme');
  assert.equal(plan.meals[0].values.food_id, null, 'gövde yeni id bekler');
});

test('UNIQUE(food_id) ihlali: yedekte aynı gıdaya ikinci besin satırı atlanır', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        foods: [{ id: 'f1', name: 'Tavuk' }],
        food_nutrition: [
          { food_id: 'f1', kcal: 100, protein_g: 1, carbs_g: 1, fat_g: 1 },
          { food_id: 'f1', kcal: 999, protein_g: 1, carbs_g: 1, fat_g: 1 },
        ],
      }),
    ),
  );
  assert.equal(plan.nutrition.length, 1);
  assert.equal(plan.skipped.food_nutrition, 1);
});

test('besin satırının gıdası yedekte yoksa atlanır (FK ihlali olmaz)', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        food_nutrition: [{ food_id: 'olmayan', kcal: 100, protein_g: 1, carbs_g: 1, fat_g: 1 }],
      }),
    ),
  );
  assert.equal(plan.nutrition.length, 0);
  assert.equal(plan.skipped.food_nutrition, 1);
});

test('tüm yemek satırları aynı gün/öğün/yemekse yalnızca ilki yazılır', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        meal_entries: [mealRow({ id: 'a' }), mealRow({ id: 'b' }), mealRow({ id: 'c' })],
      }),
    ),
  );
  assert.equal(plan.meals.length, 1);
  assert.equal(plan.skipped.meal_entries, 2);
});

// ===========================================================================
// 3) Dedup anahtarları
// ===========================================================================

test('su dedup\'u dize değil epoch üzerinden çalışır (+00:00 ↔ Z aynı kayıt)', () => {
  const a = waterInstant({ entry_time: '2026-01-01T09:00:00+00:00' }, {});
  const b = waterInstant({ entry_time: '2026-01-01T09:00:00Z' }, {});
  assert.equal(a.micros, b.micros);
  assert.equal(a.micros, Date.parse('2026-01-01T09:00:00Z') * 1000);
});

test('su kaydında entry_time yoksa gün başlangıcı türetilir ve SAYILIR', () => {
  const coerced = {};
  const when = waterInstant({ entry_date: '2026-08-15' }, coerced);
  assert.equal(when.day, '2026-08-15');
  assert.match(when.iso, /^2026-08-15T00:00:00/);
  assert.equal(coerced['water_entries.entry_time'], 1);
});

test('su kaydında ne zaman ne gün varsa ölümcül (sessiz veri kaybı olmaz)', () => {
  assert.equal(waterInstant({}, {}), null);
  assert.equal(waterInstant({ entry_time: 'bozuk' }, {}), null);
});

test('mealKey: eksik tipte anahtar üretilmez (nereye yazılacağı bilinmiyor)', () => {
  assert.equal(mealKey('2026-08-15', 'Tavuk', 'lunch'), '2026-08-15|Tavuk|lunch');
  assert.equal(mealKey('2026-08-15', null, 'lunch'), '2026-08-15||lunch');
  assert.equal(mealKey('2026-08-15', 'Tavuk', ''), null);
});

test('isDeleted: yumuşak silinmiş satır canlanmaz', () => {
  assert.equal(isDeleted({ deleted_at: '2026-08-15T10:00:00Z' }), true);
  assert.equal(isDeleted({}), false);
  assert.equal(isDeleted({ deleted_at: null }), false);
  assert.equal(isDeleted({ deleted_at: '' }), false);
});

// ===========================================================================
// 4) Tarih UTC kayması
// ===========================================================================

test('localDateFromIso UTC değil YEREL takvim gününü verir', () => {
  // 2026-03-01T00:30:00Z → UTC+03:00'te 1 Mart 03:30, yerel gün **1 Mart**.
  // `toISOString().split('T')[0]` de 1 Mart verir; UTC+03:00'te gece 00:00
  // yapılan kayıtlar ise UTC'de bir önceki gün → "dün" etiketi hatası.
  const local = new Date(2026, 2, 1, 0, 30, 0).toISOString();
  assert.equal(localDateFromIso(local), '2026-03-01');
  assert.equal(localDateFromIso(null), null);
  assert.equal(localDateFromIso('bozuk'), null);
});

test('dateString: yedekteki entry_date yalnız tarih olarak yazılır', () => {
  assert.equal(dateString('2026-08-15'), '2026-08-15');
  assert.equal(dateString(' 2026-08-15 '), '2026-08-15');
  assert.equal(dateString('değil-tarih'), null);
  assert.equal(dateString(20260815), null);
  assert.equal(dateString(undefined), null);
});

test('epochMicros: iki farklı damga biçimi aynı anahtarı üretir', () => {
  assert.equal(epochMicros('2026-01-01T09:00:00Z'), epochMicros('2026-01-01T09:00:00+00:00'));
  assert.equal(epochMicros('2026-01-01T09:00:00+03:00'), Date.parse('2026-01-01T06:00:00Z') * 1000);
  assert.equal(epochMicros('bozuk'), null);
  assert.equal(epochMicros(null), null);
});

// ===========================================================================
// 5) favorite_foods / recent_foods — dışa aktarılıyor, içe aktarılmıyordu
// ===========================================================================

test('favoriler ve son kullanılanlar plana girer (yedek→geri yüklemede kaybolmaz)', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        foods: [
          { id: 'bk-f1', name: 'Tavuk' },
          { id: 'bk-f2', name: 'Pilav' },
        ],
        favorite_foods: [
          { id: 'eski-1', user_id: 'başka-kullanıcı', food_id: 'bk-f1' },
          { id: 'eski-2', user_id: 'başka-kullanıcı', food_id: 'bk-f2' },
        ],
        recent_foods: [
          { id: 'eski-3', user_id: 'başka-kullanıcı', food_id: 'bk-f1', use_count: 9, last_used_at: '2026-08-15T12:00:00Z' },
        ],
      }),
    ),
  );
  assert.equal(plan.favorites.length, 2);
  assert.equal(plan.recents.length, 1);
  // Eşleme **ad** üzerinden yapılır; yedekteki `id` (eski kullanıcıya ait
  // UUID) `food_id` olarak yazılmaz — FK ihlali olurdu.
  assert.deepEqual(
    plan.favorites.map((f) => f.backupName).sort(),
    ['Pilav', 'Tavuk'],
  );
  assert.equal(plan.recents[0].backupName, 'Tavuk');
  // `use_count` **bilinçli olarak** DB varsayılanına (1) çekilir:
  // geri yüklemede kullanıcının gıdayı kaç kez kullandığını yedekten
  // ezmek yerine liste yeniden kurulur. `ignoreDuplicates` yazımı da
  // zaten DB'nin mevcut sayacını korur, bu yüzden plan değeri yalnızca
  // "yeni" gıdalar için anlamlıdır.
  assert.equal(plan.recents[0].values.use_count, 1, 'yedeğin 9 sayacı ezilmez');
  assert.equal(plan.coerced['recent_foods.use_count'], 1, 'bu düzeltme SAYILIR');
  assert.equal(plan.recents[0].values.last_used_at, '2026-08-15T12:00:00.000Z');
});

test('favori gıdası yedekte yoksa atlanır (FK ihlali olmaz)', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({
        favorite_foods: [{ id: 'f1', food_id: 'olmayan-gida' }, { id: 'f2' }],
      }),
    ),
  );
  assert.equal(plan.favorites.length, 0);
  assert.equal(plan.skipped.favorite_foods, 2);
});

// ===========================================================================
// 6) Gövde sözleşmesi: PGRST102, DEFAULT, ölçek sabitleri
// ===========================================================================

test('uniform: tüm satırların anahtar kümesi aynı (PGRST102)', () => {
  for (const table of IMPORT_TABLES) {
    const rows = uniform(
      [
        { values: {}, backupId: null, backupName: null, dedupKey: null },
        { values: {}, backupId: null, backupName: null, dedupKey: null },
      ],
      table,
    );
    const keys = Object.keys(rows[0]).sort();
    assert.deepEqual(Object.keys(rows[1]).sort(), keys, table);
    assert.ok(keys.length > 0, table);
  }
});

test('uniform: created_at null ise gövdeden DÜŞÜRÜLÜR (Prefer: missing=default)', () => {
  // `defaultToNull: false` kullanıldığı için null göndermek 23502 üretirdi.
  const [row] = uniform(
    [{ values: { created_at: null, user_id: 'u1' }, backupId: null, backupName: null, dedupKey: null }],
    'meal_entries',
  );
  assert.equal('created_at' in row, false);
  assert.equal(row.user_id, 'u1');
});

test('uniform: created_at doluysa taşınır (ekleme sırası korunur)', () => {
  const [row] = uniform(
    [
      {
        values: { created_at: '2026-08-15T12:00:00.000Z', user_id: 'u1' },
        backupId: null,
        backupName: null,
        dedupKey: null,
      },
    ],
    'meal_entries',
  );
  assert.equal(row.created_at, '2026-08-15T12:00:00.000Z');
});

test('in-filter URL\'i 8 KB tavanının altında kalır (2000 kayıt senaryosu)', () => {
  // 36 haneli UUID + 2 tırnak + virgül = 39 bayt.
  const uuid = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
  const worst = Array.from({ length: 2000 }, (_, i) => `${uuid.slice(0, 34)}${String(i % 1000).padStart(2, '0')}`);
  const urls = inFilterChunks(worst).map((c) => `entry_time=in.(${c.map((v) => `"${v}"`).join(',')})`);
  for (const url of urls) {
    assert.ok(url.length < 8000, `dilim ${url.length} bayt — 8 KB tavanını aşıyor`);
  }
  assert.equal(urls.length, 20, '2000 kayıt → 20 dilim');
  assert.equal(IN_FILTER_CHUNK_SIZE, 100);
});

test('boş girdi hiç dilim üretmez (PostgREST `in.()` → PGRST100)', () => {
  assert.deepEqual(inFilterChunks([]), []);
  assert.deepEqual(chunk([], 500), []);
});

test('importBatchSize Postgres parametre tavanının çok altında', () => {
  // En geniş tablo `meal_entries` = 14 kolon. 500 × 14 = 7000 ≪ 65535.
  assert.equal(IMPORT_BATCH_SIZE, 500);
  assert.ok(IMPORT_BATCH_SIZE * 14 < 65535);
});

test('tablolar bağımlılık sırasında (foods → favoriler)', () => {
  assert.deepEqual(
    [...IMPORT_TABLES],
    ['foods', 'food_nutrition', 'meal_entries', 'water_entries', 'weight_entries', 'favorite_foods', 'recent_foods'],
  );
});

// ===========================================================================
// 7) Bozuk girdi dayanıklılığı
// ===========================================================================

test('tablo değeri liste değilse atlanır (çökmez)', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(
      backup({ meal_entries: 'bu bir liste değil', water_entries: null, weight_entries: 42 }),
    ),
  );
  assert.equal(plan.meals.length, 0);
  assert.equal(plan.water.length, 0);
  assert.equal(plan.weights.length, 0);
});

test('satır içi nesne değilse atlanır', () => {
  const plan = buildImportPlan(
    USER,
    decodeBackup(backup({ meal_entries: ['metin', 5, null, mealRow({ id: 'm9' })] })),
  );
  assert.equal(plan.meals.length, 1);
});

test('öğünün entry_date\'ı okunamıyorsa ölümcül', () => {
  assert.throws(
    () => buildImportPlan(USER, decodeBackup(backup({ meal_entries: [mealRow({ entry_date: 'değil-tarih' })] }))),
    ImportValidationError,
  );
});

test('kilo günü bozuksa ölümcül (kilo trendi bozulur)', () => {
  assert.throws(
    () =>
      buildImportPlan(
        USER,
        decodeBackup(backup({ weight_entries: [{ id: 'g1', entry_date: 'bilinmiyor', weight_kg: 80 }] })),
      ),
    ImportValidationError,
  );
});

test('2000 öğünlük yedek planlanabiliyor (ölçek sınırı değil)', () => {
  // 5 yıla yayılmış benzersiz günler (2000 kayıt / 4 kayıt-gün).
  const day = (i) => {
    const d = new Date(Date.UTC(2024, 0, 1 + Math.floor(i / 4)));
    return d.toISOString().slice(0, 10);
  };
  const meals = Array.from({ length: 2000 }, (_, i) =>
    mealRow({ id: `m${i}`, entry_date: day(i), custom_name: `Yemek ${i}` }),
  );
  const plan = buildImportPlan(USER, decodeBackup(backup({ meal_entries: meals })));
  assert.equal(plan.meals.length, 2000);
  assert.equal(plan.mealDates.length, 500, 'gün başına 4 öğün → 500 benzersiz gün');
  // Varlık kontrolü bu günleri 100'lük dilimlerde sorgular.
  assert.equal(inFilterChunks(plan.mealDates).length, 5);
});
