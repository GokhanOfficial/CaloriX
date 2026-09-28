#!/usr/bin/env node
/**
 * Hesap katmanı **parite testleri** — web ↔ Flutter.
 *
 * ## Amaç
 *
 * Bu PWA bakım modunda ama kullanılıyor; Flutter ise asıl uygulama. 8 tur
 * boyunca Flutter tarafında hesap hataları tek tek düzeltildi (BMR sınırı,
 * `bmi(70,-180) = 24.2`, `progress` NaN → `UnsupportedError`, `Gender.other`
 * 166 kcal farkı) ve düzeltmeler `flutter_app/test/**` altında kilitlendi.
 * Web tarafı aynı düzeltmelerin **bir kısmını** almamıştı.
 *
 * Buradaki testler iki yönü de denetler:
 *
 *  1. **Değer paritesi** — aynı girdi iki istemcide aynı sonucu vermeli.
 *     Beklenen değerler Flutter testlerinden ve `calculations.dart` yorumlarından
 *     alındı; her birinin yanına referans satır yazıldı.
 *  2. **Sözleşme paritesi** — aşırı/bozuk girdide iki taraf **aynı** savunmayı
 *     yapmalı (0 dön, istisna atma, `NaN` üretme).
 *
 * ## `Gender.other` kararı ve kanıtı
 *
 * `Gender.other` → **erkek** (`+5`) formülü. Gerekçe `src/lib/calculations.ts`
 * içinde; buradaki testler kararı iki istemcinin gerçek sayılarıyla sabitler.
 *
 * ## Çalıştırma
 *
 * `node --experimental-strip-types --test tool/test_calculations_parity.mjs`
 *
 * Aynı mekanizma `tool/test_backup_import.mjs` ile aynıdır: ek test
 * koşucusu bağımlılığı yok, Node'un yerleşik `node:test` kullanılır.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  ACTIVITY_LEVELS,
  DEFAULT_GOALS,
  GOALS,
  activityLevelFromDb,
  activityLevelToDb,
} from '../src/lib/constants.ts';

import {
  FAT_KCAL_PER_G,
  CARBS_KCAL_PER_G,
  MAX_AGE,
  MAX_BMR,
  MAX_MEAL_AMOUNT,
  MIN_BMR,
  MIN_TARGET_CALORIES,
  PROTEIN_KCAL_PER_G,
  calculateAge,
  calculateBMR,
  calculateBMI,
  calculateMacros,
  calculateNutritionForAmount,
  calculateProgress,
  calculateTDEE,
  calculateTargetCalories,
  genderForBmr,
  getBMICategory,
  isUsableAmount,
  parseDateOnly,
  per100gFromTotals,
  waterTargetMl,
} from '../src/lib/calculations.ts';

/** `useDailyData` ve `calculations` aynı sabiti dışa açıyor (tek kaynak). */
const PER_100G_DEFAULT = { kcal: 250, protein: 20, carbs: 30, fat: 8 };

// ===========================================================================
// 1) ⭐ Gender.other — 166 kcal (P1, A3r6 aktarımı)
// ===========================================================================

test('⭐ genderForBmr: yalnız "female" kadın formülüne düşer', () => {
  assert.equal(genderForBmr('female'), 'female');
  assert.equal(genderForBmr('male'), 'male');
  // Karar: `other` → male (Flutter `Gender.other` sözleşmesi)
  assert.equal(genderForBmr('other'), 'male');
  // Kararsız veri de erkek tarafına düşer — "belirtilmemiş" ile
  // "cinsiyetsiz seçildi" aynı hesaba girer.
  assert.equal(genderForBmr(null), 'male');
  assert.equal(genderForBmr(undefined), 'male');
  assert.equal(genderForBmr(''), 'male');
  assert.equal(genderForBmr('Bilinmeyen'), 'male');
});

test('⭐ BMR: other = male DEĞİL, kadın DEĞİL — 80/175/30 → 1749', () => {
  // 10·80 + 6.25·175 − 5·30 + 5 = 800 + 1093.75 − 150 + 5 = 1749.75 → 1749
  // Dart referansı: `test/core/utils/calculations_*_test.dart` (A3r6) ve
  // A3r6 raporu: "BMR formülü doğru (80/175/30 → 1749)".
  const p = { weight: 80, height: 175, age: 30 };
  assert.equal(calculateBMR({ ...p, gender: 'other' }), 1749);
  assert.equal(calculateBMR({ ...p, gender: 'male' }), 1749);
  assert.equal(calculateBMR({ ...p, gender: 'female' }), 1583);
  // Ayrışmanın büyüklüğü: 1749 − 1583 = 166 kcal
  assert.equal(
    calculateBMR({ ...p, gender: 'male' }) - calculateBMR({ ...p, gender: 'female' }),
    166
  );
});

test('⭐ TDEE: other orta aktifte 2711 (erkek formülü), kadın 2454', () => {
  assert.equal(calculateTDEE(1749, 'moderate'), Math.round(1749 * 1.55)); // 2711
  assert.equal(calculateTDEE(1583, 'moderate'), Math.round(1583 * 1.55)); // 2454
  // 2711 − 2454 = 257 kcal/gün fark — kullanıcı iki istemcide iki hedef görüyordu.
  assert.equal(calculateTDEE(1749, 'moderate') - calculateTDEE(1583, 'moderate'), 257);
});

test('⭐ other → erkek formülü TÜM aktivite seviyelerinde erkekle aynı', () => {
  const p = { weight: 80, height: 175, age: 30 };
  for (const level of Object.keys(ACTIVITY_LEVELS)) {
    const other = calculateTDEE(calculateBMR({ ...p, gender: 'other' }), level);
    const male = calculateTDEE(calculateBMR({ ...p, gender: 'male' }), level);
    const female = calculateTDEE(calculateBMR({ ...p, gender: 'female' }), level);
    assert.equal(other, male, `${level}: other ≠ male`);
    assert.notEqual(other, female, `${level}: other = female (hata geri geldi)`);
  }
});

test('⭐ hedef kalori tabanı: other 0 BMI hedefi 1200’e düşer, kadın da düşer', () => {
  // Aşırı zayıf profilde iki taraf da güvenlik tabanına çekilir.
  const thin = { weight: 30, height: 250, age: 100, activityLevel: 'sedentary', goal: 'lose' };
  const other = calculateTargetCalories(
    calculateTDEE(calculateBMR(thin), thin.activityLevel),
    thin.goal
  );
  assert.equal(other, MIN_TARGET_CALORIES);
});

// ===========================================================================
// 2) BMR sınırları — Flutter `Calculations.bmr` ile aynı savunma
// ===========================================================================

test('BMR: sonlu olmayan girdi → minBmr (Dart `!effective.isFinite → minBmr`)', () => {
  for (const bad of [NaN, Infinity, -Infinity]) {
    assert.equal(
      calculateBMR({ weight: bad, height: 175, age: 30, gender: 'male' }),
      MIN_BMR,
      `weight=${bad}`
    );
    assert.equal(
      calculateBMR({ weight: 80, height: bad, age: 30, gender: 'male' }),
      MIN_BMR,
      `height=${bad}`
    );
    assert.equal(
      calculateBMR({ weight: 80, height: 175, age: bad, gender: 'male' }),
      MIN_BMR,
      `age=${bad}`
    );
  }
});

test('BMR: negatif BMR minBmr’a kırpılır (Dart clamp alt sınır)', () => {
  // 10·20 + 6.25·100 − 5·120 − 161 = 200 + 625 − 600 − 161 = 64 → pozitif.
  // Daha agresif: 10·10 + 6.25·100 − 5·120 − 161 = 100 + 625 − 600 − 161 = −36.
  assert.equal(
    calculateBMR({ weight: 10, height: 100, age: 120, gender: 'female' }),
    MIN_BMR
  );
});

test('BMR: üst sınır MAX_BMR (Dart `1 << 31` taşma koruması)', () => {
  const huge = calculateBMR({ weight: 1e9, height: 1e9, age: 0, gender: 'male' });
  assert.equal(huge, MAX_BMR);
});

test('BMR: 1 kg / 0 yaş bile pozitif sonuç verir (taşmaz)', () => {
  const v = calculateBMR({ weight: 1, height: 1, age: 0, gender: 'male' });
  assert.ok(Number.isSafeInteger(v), `${v} güvenli tam sayı olmalı`);
  assert.ok(v > 0 && v <= MAX_BMR);
});

// ===========================================================================
// 3) TDEE — Dart `Calculations.tdee` ile aynı
// ===========================================================================

test('TDEE: bmr ≤ 0 → 0 (Dart `if (bmr <= minBmr) return minBmr`)', () => {
  for (const bad of [0, -1, -5000, NaN, Infinity, -Infinity]) {
    assert.equal(calculateTDEE(bad, 'moderate'), MIN_BMR, `bmr=${bad}`);
  }
});

test('TDEE: bilinmeyen aktivite seviyesi → 0 (çarpım yerine güvenli taban)', () => {
  assert.equal(calculateTDEE(1800, 'ultraActive'), MIN_BMR);
  assert.equal(calculateTDEE(1800, 'VERY_ACTIVE'), MIN_BMR);
});

test('TDEE: beş seviyenin çarpanı Flutter enum ile birebir', () => {
  // `app_constants.dart` → ActivityLevel(sedentary 1.2, light 1.375,
  // moderate 1.55, active 1.725, veryActive 1.9)
  const expected = {
    sedentary: 1.2,
    light: 1.375,
    moderate: 1.55,
    active: 1.725,
    veryActive: 1.9,
  };
  assert.deepEqual(
    Object.fromEntries(
      Object.entries(ACTIVITY_LEVELS).map(([k, v]) => [k, v.multiplier])
    ),
    expected
  );
  for (const [level, mult] of Object.entries(expected)) {
    assert.equal(calculateTDEE(1749, level), Math.round(1749 * mult), level);
  }
});

// ===========================================================================
// 4) Hedef kalori — Dart `Calculations.targetCalories`
// ===========================================================================

test('hedef kalori: 1200 tabanı ve üç modifikatör', () => {
  assert.deepEqual(
    Object.fromEntries(Object.entries(GOALS).map(([k, v]) => [k, v.calorieModifier])),
    { lose: -500, maintain: 0, gain: 500 }
  );
  assert.equal(calculateTargetCalories(2000, 'maintain'), 2000);
  assert.equal(calculateTargetCalories(2000, 'lose'), 1500);
  assert.equal(calculateTargetCalories(2000, 'gain'), 2500);
  // Alt sınır: TDEE 1200 − 500 = 700 → 1200'e çekilir
  assert.equal(calculateTargetCalories(1200, 'lose'), MIN_TARGET_CALORIES);
  assert.equal(calculateTargetCalories(0, 'lose'), MIN_TARGET_CALORIES);
  // 500 + 500 = 1000 < 1200 → güvenlik tabanı
  assert.equal(calculateTargetCalories(500, 'gain'), MIN_TARGET_CALORIES);
  // Tam sınırda: 1699 + 500 = 2199 (dokunulmaz)
  assert.equal(calculateTargetCalories(1699, 'gain'), 2199);
});

test('hedef kalori: bilinmeyen hedef / sonlu olmayan TDEE → güvenli taban', () => {
  // Tanımsız enum değeri DB'den gelirse (kısıt gevşetilmiş bir migration)
  // çarpım `NaN` üretmemeli.
  assert.equal(calculateTargetCalories(2000, 'bulk'), MIN_TARGET_CALORIES);
  for (const bad of [NaN, Infinity, -Infinity]) {
    assert.equal(calculateTargetCalories(bad, 'maintain'), MIN_TARGET_CALORIES, `${bad}`);
  }
});

// ===========================================================================
// 5) Makrolar — Dart `Calculations.macros` ile aynı
// ===========================================================================

test('makro: 2000 kcal → 150/200/67 (DEFAULT_GOALS ile birebir)', () => {
  // 2000·0.30/4 = 150 · 2000·0.40/4 = 200 · 2000·0.30/9 = 66.67 → 67
  assert.deepEqual(calculateMacros(2000), { calories: 2000, protein: 150, carbs: 200, fat: 67 });
  assert.equal(calculateMacros(2000).fat, DEFAULT_GOALS.fat);
  assert.deepEqual(
    {
      calories: DEFAULT_GOALS.calories,
      protein: DEFAULT_GOALS.protein,
      carbs: DEFAULT_GOALS.carbs,
      fat: DEFAULT_GOALS.fat,
    },
    calculateMacros(DEFAULT_GOALS.calories)
  );
});

test('makro: ≤ 0 ve sonlu olmayan hedefte dört alan da 0 (Dart koruması)', () => {
  for (const bad of [0, -1, -2000, NaN, Infinity, -Infinity]) {
    assert.deepEqual(
      calculateMacros(bad),
      { calories: 0, protein: 0, carbs: 0, fat: 0 },
      `calculateMacros(${bad})`
    );
  }
});

test('makro: Atwater sabitleri 4/4/9 (fizyolojik)', () => {
  assert.deepEqual(
    [PROTEIN_KCAL_PER_G, CARBS_KCAL_PER_G, FAT_KCAL_PER_G],
    [4, 4, 9]
  );
});

test('makro: yüzde parametreleri özel oranı da destekler (yuvarlama kuralı)', () => {
  // 2000 kcal · %25/%50/%25 → 125 / 250 / 55.56 → 56
  assert.deepEqual(calculateMacros(2000, 25, 50, 25), {
    calories: 2000,
    protein: 125,
    carbs: 250,
    fat: 56,
  });
});

test('makro: hedef ile makro kalorisi yuvarlama payı içinde tutarlı', () => {
  for (const kcal of [1200, 1500, 1800, 2000, 2500, 2711, 3382, 4000]) {
    const m = calculateMacros(kcal);
    const fromMacros = m.protein * 4 + m.carbs * 4 + m.fat * 9;
    // Yuvarlama farkı: 3 makro × en fazla yarım gram ≈ ±6 kcal
    assert.ok(
      Math.abs(fromMacros - kcal) <= 6,
      `${kcal} kcal → makro ${fromMacros} kcal (fark ${Math.abs(fromMacros - kcal)})`
    );
  }
});

// ===========================================================================
// 6) BMI — Flutter `Calculations.bmi` ile aynı (A3r6 düzeltmesi)
// ===========================================================================

test('BMI: negatif boy artık "geçerli" değer üretmiyor (A3r6 hatası)', () => {
  // `bmi(70, -180)` kare pozitif olduğu için web'de **24.2** dönüyordu:
  // fiziksel olarak imkânsız kayıt "normal" görünüyordu.
  assert.equal(calculateBMI(70, -180), 0);
  assert.equal(calculateBMI(70, 0), 0);
  assert.equal(calculateBMI(-70, 180), 0);
  assert.equal(calculateBMI(0, 180), 0);
});

test('BMI: sonlu olmayan girdi → 0', () => {
  for (const bad of [NaN, Infinity, -Infinity]) {
    assert.equal(calculateBMI(bad, 180), 0, `weight=${bad}`);
    assert.equal(calculateBMI(70, bad), 0, `height=${bad}`);
  }
});

test('BMI: 80/175/30 → 26.1 (bir ondalık)', () => {
  assert.equal(calculateBMI(80, 175), 26.1);
  assert.equal(calculateBMI(70, 170), 24.2);
  assert.equal(calculateBMI(50, 160), 19.5);
});

test('BMI kategori: dört eşik iki istemcide aynı', () => {
  const cases = [
    [0, 'bmi.underweight', 'info'],
    [18.4, 'bmi.underweight', 'info'],
    [18.5, 'bmi.normal', 'success'],
    [24.9, 'bmi.normal', 'success'],
    [25, 'bmi.overweight', 'warning'],
    [29.9, 'bmi.overweight', 'warning'],
    [30, 'bmi.obese', 'destructive'],
    [45, 'bmi.obese', 'destructive'],
  ];
  for (const [bmi, labelKey, color] of cases) {
    assert.deepEqual(getBMICategory(bmi), { labelKey, color }, `BMI ${bmi}`);
  }
});

test('BMI 0 "düşük kilolu" görünüyor (hesaplanamadı → kullanıcıyı yanıltmasın)', () => {
  // `calculateBMI` imkânsız kayıtta 0 döner; kategori 0 → underweight.
  // Bu Flutter ile aynı davranıştır; ama **hesaplanamayan** bir kaydı
  // "obez" göstermekten (eski `Infinity` davranışı) kesinlikle iyidir.
  assert.equal(getBMICategory(calculateBMI(70, 0)).labelKey, 'bmi.underweight');
  assert.equal(getBMICategory(Infinity).labelKey, 'bmi.obese');
});

// ===========================================================================
// 7) İlerleme yüzdesi — Dart `Calculations.progress` ile aynı
// ===========================================================================

test('ilerleme: 0/negatif hedef → 0 (çubuk bozulmaz)', () => {
  for (const bad of [0, -1, -2000]) {
    assert.equal(calculateProgress(500, bad), 0, `target=${bad}`);
  }
});

test('ilerleme: sonlu olmayan → 0 (NaN/Infinity yayılmaz)', () => {
  for (const bad of [NaN, Infinity, -Infinity]) {
    assert.equal(calculateProgress(500, bad), 0, `target=${bad}`);
    assert.equal(calculateProgress(bad, 2000), 0, `current=${bad}`);
  }
});

test('ilerleme: 0..100 aralığına kırpılır (aşım 100, eksi 0)', () => {
  assert.equal(calculateProgress(1000, 2000), 50);
  assert.equal(calculateProgress(3000, 2000), 100);
  assert.equal(calculateProgress(-100, 2000), 0);
});

// ===========================================================================
// 8) Su hedefi — Dart `Calculations.waterTargetMl` ile aynı
// ===========================================================================

test('su hedefi: kg × 33, sonlu olmayanda 0 (NaN profile yazılıyordu)', () => {
  assert.equal(waterTargetMl(70), 2310);
  assert.equal(waterTargetMl(80), 2640);
  assert.equal(waterTargetMl(0), 0);
  assert.equal(waterTargetMl(-50), 0);
  for (const bad of [NaN, Infinity, -Infinity]) {
    assert.equal(waterTargetMl(bad), 0, `${bad}`);
  }
});

// ===========================================================================
// 9) 100 g karşılığı — Flutter `FoodRepository.customItem` ile aynı
// ===========================================================================

test('per100g: amount = 0 artık NaN üretmiyor (NaN/Infinity → 100 g varsayılanı)', () => {
  // Web'de `0/0` → `NaN`, Dart'ta `Infinity.round()` **istisna fırlatıyor**
  // ve favoriler/son-kullanılanlar listesi tümüyle çöküyordu.
  const totals = { kcal: 500, protein: 30, carbs: 40, fat: 10 };
  assert.deepEqual(per100gFromTotals(totals, 0), per100gFromTotals(totals, 100));
  assert.deepEqual(per100gFromTotals(totals, -50), per100gFromTotals(totals, 100));
  assert.deepEqual(per100gFromTotals(totals, NaN), per100gFromTotals(totals, 100));
  for (const v of Object.values(per100gFromTotals(totals, 0))) {
    assert.ok(Number.isFinite(v), `${v} sonlu olmalı`);
  }
});

test('per100g: 100 g bölümü birebir (200 gramda 500 kcal → 250)', () => {
  const totals = { kcal: 500, protein: 30, carbs: 40, fat: 10 };
  assert.deepEqual(per100gFromTotals(totals, 200), {
    kcal: 250,
    protein: 15,
    carbs: 20,
    fat: 5,
  });
  // 100 g bölümü: 500 / 100 · 100 = 500
  assert.deepEqual(per100gFromTotals(totals, 100), {
    kcal: 500,
    protein: 30,
    carbs: 40,
    fat: 10,
  });
});

test('per100g: sonlu olmayan besin değeri 0 (Infinity yayılmaz)', () => {
  const out = per100gFromTotals(
    { kcal: Infinity, protein: NaN, carbs: -Infinity, fat: 10 },
    100
  );
  assert.deepEqual(out, { kcal: 0, protein: 0, carbs: 0, fat: 10 });
});

test('per100g ∘ calculateNutritionForAmount = birim (100 g girdi)', () => {
  const per100 = { kcal: 250, protein: 20, carbs: 30, fat: 8 };
  // 100 g karşılığından 150 g'lik toplam üret, sonra geri dönüştür.
  // 250/150·100 = 166.67 → 167 · 20/150·100 = 13.33 → 13.3 · 30 → 20 · 8 → 5.33 → 5.3
  const totals = per100gFromTotals(per100, 150);
  assert.deepEqual(totals, { kcal: 167, protein: 13.3, carbs: 20, fat: 5.3 });
  // Geri dönüşüm: yuvarlama hataları **neredeyse** birbirini götürür.
  // Makro alanlar birebir döner; kalori 167 · 1.5 = 250.5 → 251 (1 kcal).
  // Ölçüm: 251/20/30/8. Bu, favori kartındaki 100 g değerlerinin
  // girilen değerlerden **en fazla 1 kcal / 0.1 g** saptığını garanti eder.
  const back = calculateNutritionForAmount(totals, 150);
  assert.deepEqual(
    back,
    { kcal: 251, protein: 20, carbs: 30, fat: 8 },
    'yuvarlama payı 1 kcal / 0.1 g içinde kalmalı'
  );
  for (const key of ['protein', 'carbs', 'fat']) {
    assert.ok(Math.abs(back[key] - per100[key]) <= 0.1, `${key} kayması ≤ 0.1`);
  }
});

test('calculateNutritionForAmount: 0/negatif/NaN miktar → dört alan 0', () => {
  const per100 = { kcal: 250, protein: 20, carbs: 30, fat: 8 };
  for (const bad of [0, -1, NaN, Infinity, -Infinity]) {
    assert.deepEqual(
      calculateNutritionForAmount(per100, bad),
      { kcal: 0, protein: 0, carbs: 0, fat: 0 },
      `${bad}`
    );
  }
});

test('calculateNutritionForAmount: ondalık basamaklar korunur', () => {
  // 123.456/100 = 1.23456 →
  //   250·1.23456 = 308.64  → 309   (0 ondalık)
  //    20·1.23456 =  24.691 → 24.7  (1 ondalık)
  //    30·1.23456 =  37.037 → 37
  //     8·1.23456 =   9.876 → 9.9
  assert.deepEqual(calculateNutritionForAmount(PER_100G_DEFAULT, 123.456), {
    kcal: 309,
    protein: 24.7,
    carbs: 37,
    fat: 9.9,
  });
});

// ===========================================================================
// 10) Miktar sözleşmesi — Flutter `isUsableAmount` + DB CHECK
// ===========================================================================

test('isUsableAmount: DB CHECK ile aynı aralık (0 < x ≤ 10000)', () => {
  assert.equal(MAX_MEAL_AMOUNT, 10000);
  for (const good of [1, 100, 250, 10000]) {
    assert.equal(isUsableAmount(good), true, `${good} geçerli olmalı`);
  }
  for (const bad of [0, -1, -0.5, 10001, 1e9, NaN, Infinity, -Infinity, null, undefined, '100']) {
    assert.equal(isUsableAmount(bad), false, `${String(bad)} reddedilmeli`);
  }
});

// ===========================================================================
// 11) Yaş hesabı — DST değil ama **ayrıştırma tuzağı** var
// ===========================================================================

test('parseDateOnly: ISO tarih dizesi yerel gün, UTC değil', () => {
  // `new Date("2000-01-15")` UTC gece yarısı → Türkiye'de (UTC+03:00)
  // `getDate()` 14 döner ve yaş **bir gün önce** ilerler.
  const d = parseDateOnly('2000-01-15');
  assert.ok(d, 'geçerli Date dönmeli');
  assert.equal(d.getFullYear(), 2000);
  assert.equal(d.getMonth(), 0);
  assert.equal(d.getDate(), 15);
  assert.equal(d.getHours(), 0);
});

test('parseDateOnly: olmayan gün (taşma) → NaN Date', () => {
  // `new Date(2026, 1, 30)` 1 Mart'a kayar → 30 Şubat yok.
  const d = parseDateOnly('2026-02-30');
  assert.ok(d === null || Number.isNaN(d.getTime()));
});

test('parseDateOnly: bozuk girdi → NaN/null', () => {
  for (const bad of ['', '   ', 'abc', '15/01/2000', '0000-00-00', '2026-13-45']) {
    const d = parseDateOnly(bad);
    assert.ok(d === null || Number.isNaN(d.getTime()), `"${bad}" geçerli olmamalı`);
  }
});

test('calculateAge: doğum günü gelmeden yaş artmaz', () => {
  const now = new Date();
  const y = now.getFullYear();
  // Bugünün doğum günü → 30
  const todayBirth = new Date(y - 30, now.getMonth(), now.getDate());
  // Yarının doğum günü → henüz gelmedi, yaş 29
  const tomorrowBirth = new Date(y - 30, now.getMonth(), now.getDate() + 1);
  assert.equal(calculateAge(todayBirth), 30, 'bugün doğan 30 yaşında');
  assert.equal(calculateAge(tomorrowBirth), 29, 'yarın doğan henüz 29');
});

test('calculateAge: 120 yaş üstü kayıt MAX_AGE ile sınırlı', () => {
  // Web'de üst sınır **yoktu**: 1800 doğum yılı BMR'yi -1900 yapıyordu.
  assert.equal(MAX_AGE, 120);
  assert.equal(calculateAge(new Date(1700, 0, 1)), MAX_AGE);
  assert.equal(calculateAge(new Date(1800, 0, 1)), MAX_AGE);
});

test('calculateAge: gelecek doğum tarihi 0 döner (negatif yaş yok)', () => {
  const future = new Date();
  future.setFullYear(future.getFullYear() + 5);
  assert.equal(calculateAge(future), 0);
});

test('calculateAge: 29 Şubat doğumlu yılda bir gün kaymıyor', () => {
  // `Math.floor((now - birth) / 365.25 gün)` deseni 29 Şubat'ta yılda bir gün
  // kaydırıyordu (A5'ın `Index.tsx` düzeltmesinin gerekçesi). Takvim yılı
  // farkı tabanlı hesap buna duyarsız.
  const leap = new Date(2000, 1, 29);
  const age = calculateAge(leap);
  const expectedRaw = new Date().getFullYear() - 2000;
  const m = new Date().getMonth();
  const expected =
    m < 1 || (m === 1 && new Date().getDate() < 29) ? expectedRaw - 1 : expectedRaw;
  assert.equal(age, Math.max(0, Math.min(expected, MAX_AGE)));
});

// ===========================================================================
// 12) Aktivite seviyesi eşleyicisi — iki istemci, iki isimlendirme
// ===========================================================================

test('activityLevelToDb: camelCase → DB snake_case (CHECK kısıtı)', () => {
  assert.equal(activityLevelToDb('veryActive'), 'very_active');
  for (const level of Object.keys(ACTIVITY_LEVELS)) {
    const db = activityLevelToDb(level);
    assert.match(db, /^(sedentary|light|moderate|active|very_active)$/, db);
  }
});

test('activityLevelFromDb: snake_case → camelCase, bilinmeyen → moderate', () => {
  assert.equal(activityLevelFromDb('very_active'), 'veryActive');
  assert.equal(activityLevelFromDb('moderate'), 'moderate');
  for (const db of ['sedentary', 'light', 'moderate', 'active', 'very_active']) {
    // Round-trip: DB → UI → DB kayıp yok
    assert.equal(activityLevelToDb(activityLevelFromDb(db)), db, db);
  }
  assert.equal(activityLevelFromDb(null), 'moderate');
  assert.equal(activityLevelFromDb(undefined), 'moderate');
  assert.equal(activityLevelFromDb('uçuk'), 'moderate');
});

// ===========================================================================
// 13) Uçtan uca: iki istemci aynı girdiden aynı hedefi üretir
// ===========================================================================

test('⭐ uçtan uca parite: 8 adet gerçekçi profil, iki cinsiyet kuralı', () => {
  const profiles = [
    { weight: 45, height: 158, age: 22, activityLevel: 'light', goal: 'lose' },
    { weight: 60, height: 168, age: 30, activityLevel: 'moderate', goal: 'maintain' },
    { weight: 80, height: 175, age: 30, activityLevel: 'moderate', goal: 'maintain' },
    { weight: 95, height: 182, age: 45, activityLevel: 'active', goal: 'lose' },
    { weight: 72, height: 170, age: 28, activityLevel: 'veryActive', goal: 'gain' },
    { weight: 55, height: 162, age: 19, activityLevel: 'sedentary', goal: 'maintain' },
    { weight: 110, height: 190, age: 55, activityLevel: 'light', goal: 'lose' },
    { weight: 38, height: 150, age: 25, activityLevel: 'active', goal: 'gain' },
  ];
  for (const p of profiles) {
    for (const gender of ['male', 'female', 'other', null]) {
      const bmr = calculateBMR({ ...p, gender });
      const tdee = calculateTDEE(bmr, p.activityLevel);
      const kcal = calculateTargetCalories(tdee, p.goal);
      const m = calculateMacros(kcal);
      // Zincirin tamamı sonlu ve tutarlı olmalı
      for (const v of [bmr, tdee, kcal, m.protein, m.carbs, m.fat, calculateBMI(p.weight, p.height)]) {
        assert.ok(Number.isFinite(v), `${gender}/${p.weight}kg → ${v}`);
      }
      assert.ok(bmr >= MIN_BMR && bmr <= MAX_BMR);
      assert.ok(tdee >= MIN_BMR);
      assert.ok(kcal >= MIN_TARGET_CALORIES);
      // `other` erkekle aynı
      if (gender === 'other' || gender === null) {
        assert.equal(bmr, calculateBMR({ ...p, gender: 'male' }), `${p.weight}kg`);
      }
    }
  }
});

test('A3r6 raporundaki somut vaka: 30y/erkek/175/80/çok-aktif → 3382 kcal hedef', () => {
  // TRANSFER-defteri T4: "very_active DB değeri moderate sayılıyordu;
  // doğrusu veryActive (1.90) … 30y/erkek/175cm/80kg → 2759 yerine 3382".
  const bmr = calculateBMR({ weight: 80, height: 175, age: 30, gender: 'male' });
  assert.equal(bmr, 1749);
  assert.equal(calculateTDEE(bmr, 'veryActive'), Math.round(1749 * 1.9)); // 3323
  assert.equal(calculateTDEE(bmr, 'moderate'), 2711);
  // very_active yanlış okunduğunda (eski hata) 2711, doğrusunda 3323.
  assert.equal(calculateTDEE(bmr, 'veryActive') - calculateTDEE(bmr, 'moderate'), 612);
});
