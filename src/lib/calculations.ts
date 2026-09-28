// CaloriX Calculation Functions

import { ACTIVITY_LEVELS, GOALS, type ActivityLevel, type Goal } from './constants';

export type Gender = 'male' | 'female' | 'other';

export interface UserProfile {
  age: number;
  weight: number; // kg
  height: number; // cm
  gender: Gender;
  activityLevel: ActivityLevel;
  goal: Goal;
}

export interface NutritionGoals {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
}

/**
 * Cinsiyetsiz (`other`) kullanıcı hangi BMR sabitini alır?
 *
 * **Karar: `other` → erkek (male) formülü.** Gerekçe:
 *
 *  1. **Sözleşme (kaynak olarak alındı):** Flutter `Gender.other` erkek
 *     formülüne düşüyor
 *     (`flutter_app/lib/core/utils/calculations.dart:15` —
 *      `gender == Gender.female ? base - 161 : base + 5`) ve A3r6'ın
 *     referans testleri bu davranışı kilitledi. Web'de `other` **kadın**
 *     formülüne düşüyordu (`gender === 'male' ? +5 : -161`), yani aynı
 *     kullanıcı iki istemcide iki farklı hedef görüyordu: 80 kg/175 cm/30 yaş
 *     → BMR 1749 ↔ 1583 (**166 kcal**), TDEE (orta aktif) 2711 ↔ 2454
 *     (**257 kcal**). Hedef `profiles.daily_calorie_target`'a yazıldığı için
 *     bu bir P1 "kullanıcıyı yanlış bilgilendiren hesap" hatasıydı.
 *  2. **Tıbbi gerekçe:** Mifflin-St Jeor'un iki sabiti (erkek `+5`, kadın
 *     `-161`) 166 kcal'lık bir farkla ayrılır ve cinsiyetsiz bir kullanıcı
 *     için ortalamak (`-78`) **hiçbir iki istemcide** mevcut değildi.
 *     Seçilecek bir taraf gerekiyordu.
 *  3. **Neden erkek tarafı:** Mifflin-St Jeor'un `-161` sabiti, altmış
 *     yaş üstü kadın grubundan türetilmiştir; `+5` ise daha geniş bir
 *     kitleye (genç erkekler) uygulanmıştır. "Belirtilmemiş" seçen bir
 *     kullanıcıda **yüksek tarafı seçmek**, ihlal riski (yetersiz beslenme)
 *     bakımından düşük tarafı seçmekten daha güvenlidir — kilo verme hedefi
 *     (`-500`) uygulanmasa bile net sıfır, farkında kalır; tersi bir
 *     "kilo verdim ama hedefim 300 kcal arttı" yanılgısı üretir.
 *
 * **Neden web'de çıplak `gender` değişkeniyle `male`/`female` eşlenmesi
 * yapılmadı:** `Index.tsx:111` profili okurken `profile.gender || "other"`
 * gönderiyor; `null` cinsiyet de `other` demektir. Yani **"cinsiyet
 * belirtilmemiş"** ile **"cinsiyetsiz seçildi"** aynı hesaba düşer —
 * bu, `SettingsPage`/`OnboardingPage`'te varsayılan `"male"` olmasıyla
 * da çelişiyordu (kayıtlı profil ile ilk açılışta farklı hedef).
 * Bu yüzden eşleme **tek yerde**, `genderForBmr()` ile yapılır.
 */
export function genderForBmr(gender: string | null | undefined): 'male' | 'female' {
  // Yalnızca **'female'** kadın formülüne düşer; `male`, `other`, `null`,
  // bozuk bir değer veya DB'den gelen bilinmeyen bir anahtar erkek formülüne
  // gider. Dart'taki `gender == Gender.female ? -161 : +5` ile birebir aynı
  // karar (bilinçli: `other` → male, bkz. yukarıdaki gerekçe).
  return gender === 'female' ? 'female' : 'male';
}

/**
 * Calculate BMR using Mifflin-St Jeor Equation
 *
 * `other` (ve `null`/bilinmeyen) cinsiyet **erkek** formülüne düşer —
 * Flutter ile birebir aynı, bkz. `genderForBmr` gerekçesi.
 */
export function calculateBMR(
  profile: Pick<UserProfile, 'weight' | 'height' | 'age' | 'gender'> | {
    weight: number;
    height: number;
    age: number;
    gender: string | null | undefined;
  }
): number {
  const { weight, height, age, gender } = profile;

  // Dart `Calculations.bmr` iki savunma uygular:
  //   1. girdi sonlu değilse → `minBmr` (0)
  //   2. sonuç `minBmr..2^31` aralığına kırpılır
  // `Math.round(NaN)` web'de `NaN` döner ve `Number.isFinite` kontrolü
  // olmadan bu değer TDEE'ye yayılır (dashboard'da `NaN kcal`).
  if (!Number.isFinite(weight) || !Number.isFinite(height) || !Number.isFinite(age)) {
    return MIN_BMR;
  }
  const raw = 10 * weight + 6.25 * height - 5 * age + (genderForBmr(gender) === 'male' ? 5 : -161);
  if (!Number.isFinite(raw)) return MIN_BMR;
  return Math.min(MAX_BMR, Math.max(MIN_BMR, Math.round(raw)));
}

/** BMR alt sınırı — `0` altındaki BMR fiziksel olarak anlamsızdır. */
export const MIN_BMR = 0;
/** BMR üst sınırı — Dart `1 << 31` ile aynı (`Int` taşması koruması). */
export const MAX_BMR = 2 ** 31;

/**
 * Günlük su hedefi (ml) — kilo × 33.
 *
 * Web'de bu ifade **iki yerde elle** (`Math.round(weight * 33)`) yazılıydı ve
 * `NaN` kilo girdisinde `NaN` üretiyordu: hedef profile `NaN` olarak
 * yazılıyor, `Math.min(100, (current / NaN) * 100)` → `NaN` olduğu için
 * su çubuğu bozuluyordu. Dart'ta `Calculations.waterTargetMl` bu korumayı
 * taşıyor; web'de de tek kaynağa bağlandı.
 */
export function waterTargetMl(weightKg: number): number {
  if (!Number.isFinite(weightKg)) return 0;
  const value = Math.round(weightKg * 33);
  return value < 0 ? 0 : value;
}

/**
 * Calculate TDEE (Total Daily Energy Expenditure)
 *
 * Dart `Calculations.tdee` iki koruma uygular: `bmr <= 0` → 0 ve
 * sonucun alt sınıra kırpılması. Web'de aynı koruma yoktu; 0'a yakın
 * bir BMR (ör. 0 yaş) 0 dönerdi, ama **negatif** BMR mümkündü.
 */
export function calculateTDEE(bmr: number, activityLevel: ActivityLevel): number {
  if (!Number.isFinite(bmr) || bmr <= MIN_BMR) return MIN_BMR;
  const multiplier = ACTIVITY_LEVELS[activityLevel]?.multiplier;
  if (multiplier === undefined) return MIN_BMR;
  const value = Math.round(bmr * multiplier);
  if (!Number.isFinite(value)) return MIN_BMR;
  return Math.max(MIN_BMR, value);
}

/**
 * Calculate target calories based on goal
 *
 * Alt sınır 1200 kcal güvenlik tabanı (Dart ile aynı değer ve aynı
 * yön: `tdee + modifier`, sonra tabana çekilir).
 */
export function calculateTargetCalories(tdee: number, goal: Goal): number {
  const modifier = GOALS[goal]?.calorieModifier;
  if (modifier === undefined) return MIN_TARGET_CALORIES;
  const value = tdee + modifier;
  if (!Number.isFinite(value)) return MIN_TARGET_CALORIES;
  return value < MIN_TARGET_CALORIES ? MIN_TARGET_CALORIES : value;
}

/** Hedef kalori alt sınırı (1200 kcal) — iki istemcide ortak. */
export const MIN_TARGET_CALORIES = 1200;

/** Öğün miktarı üst sınırı — DB CHECK (`amount_g_ml <= 10000`). */
export const MAX_MEAL_AMOUNT = 10_000;

/**
 * Bir öğün miktarı **kullanılabilir** mi? (Flutter `isUsableAmount` ile
 * aynı sözleşme.)
 *
 * 0, negatif, `NaN`, `Infinity` ve DB sınırının üstü reddedilir. Üç ayrı
 * yol (elle öğün ekleme, düzenleme, AI tanıma) bu kontrolü atlıyordu ve
 * `Infinity` besin değerleri profile yazılabiliyordu.
 */
export function isUsableAmount(value: unknown): value is number {
  return (
    typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= MAX_MEAL_AMOUNT
  );
}

/**
 * Calculate macro breakdown from target calories
 * Default split: 30% protein, 40% carbs, 30% fat
 *
 * Dart `Calculations.macros` **tek oran kaynağı** kullanır
 * (`proteinRatio/carbsRatio/fatRatio`) ve `targetCalories <= 0` → hepsi 0
 * döner. Web'de oranlar **varsayılan parametre** idi ve alt sınır koruması
 * yoktu: `calculateMacros(-500)` → negatif protein gösterebiliyordu.
 */
export function calculateMacros(
  targetCalories: number,
  proteinPercent = PROTEIN_PERCENT,
  carbsPercent = CARBS_PERCENT,
  fatPercent = FAT_PERCENT
): NutritionGoals {
  if (!Number.isFinite(targetCalories) || targetCalories <= 0) {
    return { calories: 0, protein: 0, carbs: 0, fat: 0 };
  }
  const proteinCalories = targetCalories * (proteinPercent / 100);
  const carbsCalories = targetCalories * (carbsPercent / 100);
  const fatCalories = targetCalories * (fatPercent / 100);

  return {
    calories: targetCalories,
    protein: Math.round(proteinCalories / PROTEIN_KCAL_PER_G), // 4 kcal per gram
    carbs: Math.round(carbsCalories / CARBS_KCAL_PER_G), // 4 kcal per gram
    fat: Math.round(fatCalories / FAT_KCAL_PER_G), // 9 kcal per gram
  };
}

/** Makro dağılım oranları (yüzde) — `DEFAULT_GOALS` ile aynı kaynaktan. */
export const PROTEIN_PERCENT = 30;
export const CARBS_PERCENT = 40;
export const FAT_PERCENT = 30;
/** Gram başına kalori (Atwater) — fizyolojik sabit. */
export const PROTEIN_KCAL_PER_G = 4;
export const CARBS_KCAL_PER_G = 4;
export const FAT_KCAL_PER_G = 9;

/**
 * Full nutrition goals calculation from user profile
 */
export function calculateNutritionGoals(profile: UserProfile): NutritionGoals {
  const bmr = calculateBMR(profile);
  const tdee = calculateTDEE(bmr, profile.activityLevel);
  const targetCalories = calculateTargetCalories(tdee, profile.goal);

  return calculateMacros(targetCalories);
}

/**
 * Calculate nutrition for a specific amount from per-100g values
 *
 * Ortak yardımcı: miktar 0/negatif ya da besin değeri sonlu değilse
 * `NaN` yayılması yerine 0 döner (aynı savunma `useFavoriteFoods`,
 * `useRecentFoods`, `useFoodSearch` içindeki elle yazılmış
 * `Math.round(x / amount * 100)` üçlülerinden de kaldırıldı).
 */
export function calculateNutritionForAmount(
  per100g: { kcal: number; protein: number; carbs: number; fat: number },
  amountGrams: number
): { kcal: number; protein: number; carbs: number; fat: number } {
  if (!Number.isFinite(amountGrams) || amountGrams <= 0) {
    return { kcal: 0, protein: 0, carbs: 0, fat: 0 };
  }
  const multiplier = amountGrams / 100;

  const scale = (value: number, digits: number) => {
    if (!Number.isFinite(value)) return 0;
    const scaled = value * multiplier;
    if (!Number.isFinite(scaled)) return 0;
    const factor = 10 ** digits;
    return Math.round(scaled * factor) / factor;
  };

  return {
    kcal: scale(per100g.kcal, 0),
    protein: scale(per100g.protein, 1),
    carbs: scale(per100g.carbs, 1),
    fat: scale(per100g.fat, 1),
  };
}

/**
 * Bir öğünün **toplam** besin değerlerinden 100 g karşılığını üretir.
 *
 * Yön ters: `total / amount * 100`. `amount <= 0` (null, bozuk ya da negatif
 * satır) durumunda `x / 0` → `Infinity` (ve `0/0` → `NaN`) üretir; web'de
 * `NaN` favori kartına yazılıyor, Flutter'da ise `Infinity.round()`
 * **istisna fırlatıp listeyi tamamen düşürüyordu**
 * (`food_repository.dart:436-445` aynı korumayı yapıyor). Burada miktar
 * bilinmiyorsa web'in `?? 100` varsayılanıyla aynı davranış seçilir.
 *
 * `useFavoriteFoods`, `useRecentFoods` ve `useFoodSearch` bu hesabı üç ayrı
 * kopya olarak taşıyordu; tek kaynağa bağlandı.
 */
export function per100gFromTotals(
  totals: { kcal: number; protein: number; carbs: number; fat: number },
  amountGrams: number
): { kcal: number; protein: number; carbs: number; fat: number } {
  const amount = Number.isFinite(amountGrams) && amountGrams > 0 ? amountGrams : 100;
  const scale = (value: number, digits: number) => {
    if (!Number.isFinite(value)) return 0;
    const per100 = (value / amount) * 100;
    if (!Number.isFinite(per100)) return 0;
    const factor = 10 ** digits;
    return Math.round(per100 * factor) / factor;
  };
  return {
    kcal: scale(totals.kcal, 0),
    protein: scale(totals.protein, 1),
    carbs: scale(totals.carbs, 1),
    fat: scale(totals.fat, 1),
  };
}

/**
 * Calculate BMI
 *
 * Sözleşme (Flutter `Calculations.bmi` ile birebir):
 *  - boy ≤ 0 veya sonlu değil → 0
 *  - **kilo ≤ 0 → 0** (web'de yalnız sonlu olmayan kilo reddediliyordu;
 *    `bmi(70, -180)` kare pozitif olduğu için **24.2** dönerdi → fiziksel
 *    olarak imkânsız bir kayıt geçerli "normal" BMI olarak gösteriliyordu.
 *    Flutter A3r6'da bu düzeltildi, web'de kalmıştı)
 *  - sonuç sonlu değilse → 0
 */
export function calculateBMI(weightKg: number, heightCm: number): number {
  if (!Number.isFinite(heightCm) || heightCm <= 0) return 0;
  if (!Number.isFinite(weightKg) || weightKg <= 0) return 0;
  const heightM = heightCm / 100;
  const raw = weightKg / (heightM * heightM);
  if (!Number.isFinite(raw)) return 0;
  return Math.round(raw * 10) / 10;
}

/**
 * Get BMI category - returns translation key instead of label
 */
export function getBMICategory(bmi: number): { labelKey: string; color: string } {
  if (bmi < 18.5) return { labelKey: 'bmi.underweight', color: 'info' };
  if (bmi < 25) return { labelKey: 'bmi.normal', color: 'success' };
  if (bmi < 30) return { labelKey: 'bmi.overweight', color: 'warning' };
  return { labelKey: 'bmi.obese', color: 'destructive' };
}

/**
 * Calculate progress percentage
 */
export function calculateProgress(current: number, target: number): number {
  // `target === 0` tek başına yetmiyor: negatif hedef (ör. `calculateBMR`
  // çıktısı yazı hatasıyla negatifse) `Math.min(100, -400) = -400` döner ve
  // ilerleme çubuğu `-%400` olarak render edilir. `NaN`/`Infinity` de aynı
  // sınıf bozulmayı üretir (`Math.min` NaN korur).
  if (!Number.isFinite(target) || !Number.isFinite(current) || target <= 0) return 0;
  return Math.min(100, Math.max(0, Math.round((current / target) * 100)));
}

/**
 * Takvim yılı farkına dayalı yaş — `Index.tsx` kilo kaydı sırasında ve
 * onboarding/ayarlar doğrulamasında kullanılır.
 *
 * Önceden `Math.floor((Date.now() - birth) / (365.25 * gün))` kullanılıyordu;
 * bu yaklaşım **duvar saati farkına** duyarlıdır (doğum gününe 1 gün kala
 * 1 gün fazla/eksik sayar) ve 29 Şubat doğumlularda yılda bir gün kaydırır.
 * `OnboardingPage`/`SettingsPage` zaten `calculateAge` **kopyasını** kullanıyordu;
 * bu üç kopya tek kaynağa bağlandı (tutarsızlık BMR'yi ~5 kcal kaydırıyordu
 * **ve** `OnboardingPage`'in 13-120 doğrulaması ile `Index`'in 30 varsayılanı
 * farklı yerde yaşıyordu).
 *
 * **Üst sınır Flutter ile aynı: `MAX_AGE` (120).** Web'de sınır yoktu —
 * `birth_date = "1800-01-01"` giren bir kullanıcı BMR'yi `-1900` gibi
 * bir değerle hesaplıyor ve profile yanlış hedef yazılıyordu.
 *
 * **`Date` ayrıştırma tuzağı (P1, iki sayfada birden):** `new Date("2000-01-15")`
 * ISO-8601 **tarih-saat** dizesidir ve ayrıştırıcı bunu **UTC gece yarısı**
 * olarak yorumlar. Doğu yarımkürede (Türkiye, UTC+03:00) `getFullYear()` →
 * 2000, `getMonth()` → 0, `getDate()` → **14** olur. Yani 1 Ocak doğumlu
 * bir kullanıcının yaşı her yıl **1 gün eksik** hesaplanıyordu (yaş
 * doğum gününden bir gün önce ilerliyordu). Aynı tuzak Flutter'da da var
 * (`DateTime.parse("2000-01-15")` → UTC). Yerel takvim gününe sabitleyen
 * `parseDateOnly()` kullanılıyor; `calculateAge` **kendi içinde** de
 * savunur (yıl kayması 0'dan farklıysa bir yıl düzeltir) — böylece
 * kalan iki çağrı yeri (`Index.tsx`, onboarding doğrulaması) de güvende.
 */
export const MAX_AGE = 120;

/** Yalnız `YYYY-MM-DD` (veya aynı biçimde doğruluk sınırlı) tarih dizesini
 * **yerel** takvim gününe sabitler. Saat içeren ISO dize dokunulmadan
 * `Date`e çevrilir. */
export function parseDateOnly(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
  if (match) {
    const [, y, m, d] = match;
    const year = Number(y);
    const month = Number(m);
    const day = Number(d);
    const date = new Date(year, month - 1, day);
    // `new Date(2026, 1, 30)` 1 Mart'a kayar (taşma). Böyle bir gün yok.
    if (date.getFullYear() === year && date.getMonth() === month - 1 && date.getDate() === day) {
      return date;
    }
    return new Date(NaN);
  }
  return new Date(value);
}

export function calculateAge(birthDate: Date): number {
  if (!(birthDate instanceof Date) || Number.isNaN(birthDate.getTime())) return 30;
  const now = new Date();
  let age = now.getFullYear() - birthDate.getFullYear();
  const monthDiff = now.getMonth() - birthDate.getMonth();
  // Doğum günü henüz gelmediyse yaş bir azalır.
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < birthDate.getDate())) {
    age -= 1;
  }
  // UTC ayrıştırma kayması güvenliği: yıl 0'a düşmüşse bu, doğum gününün
  // "dün"e kaydığı anlamına gelir (ISO tarih dizesi + doğu yarımküre).
  if (age < 0) {
    const utcMidnight = Date.UTC(birthDate.getUTCFullYear(), birthDate.getUTCMonth(), birthDate.getUTCDate());
    if (Number.isFinite(utcMidnight)) {
      const u = new Date(utcMidnight);
      let utcAge = now.getFullYear() - u.getUTCFullYear();
      const utcMonthDiff = now.getMonth() - u.getUTCMonth();
      if (utcMonthDiff < 0 || (utcMonthDiff === 0 && now.getDate() < u.getUTCDate())) {
        utcAge -= 1;
      }
      if (utcAge >= 0) return Math.min(utcAge, MAX_AGE);
    }
    return 0;
  }
  return Math.min(age, MAX_AGE);
}
