// CaloriX Constants

export const APP_VERSION = '1.1.0';

export const MEAL_TYPES = {
  breakfast: { id: 'breakfast', label: 'Kahvaltı', icon: '🌅', order: 1 },
  lunch: { id: 'lunch', label: 'Öğle', icon: '☀️', order: 2 },
  dinner: { id: 'dinner', label: 'Akşam', icon: '🌙', order: 3 },
  snack: { id: 'snack', label: 'Atıştırmalık', icon: '🍎', order: 4 },
} as const;

export type MealType = keyof typeof MEAL_TYPES;

export const WATER_QUICK_ADD = [250, 500] as const;

export const DEFAULT_GOALS = {
  calories: 2000,
  protein: 150,
  carbs: 200,
  // `2000 × 0.30 ÷ 9 = 66.67 → 67`. Değer 65 idi; hem Flutter
  // (`AppConstants.defaultFat`, A3 `be8158a` ile 67'ye düzeltildi) hem de
  // `calculateMacros(2000)` 67 döndürüyordu — profil kaydı olmayan kullanıcı
  // dashboard'da yanlış yağ hedefi görüyordu. `tool/check_versions.cjs`
  // artık **her iki istemciyi** de karşılaştırıyor.
  fat: 67,
  water: 2500,
};

export const ACTIVITY_LEVELS = {
  sedentary: { id: 'sedentary', label: 'Hareketsiz', multiplier: 1.2 },
  light: { id: 'light', label: 'Hafif Aktif', multiplier: 1.375 },
  moderate: { id: 'moderate', label: 'Orta Aktif', multiplier: 1.55 },
  active: { id: 'active', label: 'Aktif', multiplier: 1.725 },
  veryActive: { id: 'veryActive', label: 'Çok Aktif', multiplier: 1.9 },
} as const;

export type ActivityLevel = keyof typeof ACTIVITY_LEVELS;

/**
 * `ActivityLevel` UI anahtarları camelCase (`veryActive`), veritabanı CHECK
 * kısıtı ise snake_case (`very_active`) bekliyor:
 *   supabase/migrations/20260111041204_...sql:39
 *     activity_level TEXT CHECK (activity_level IN ('sedentary','light',
 *       'moderate','active','very_active'))
 * `calculate-macros` edge function da yalnızca snake_case kabul ediyor
 * (supabase/functions/calculate-macros/index.ts:21).
 * Bu eşleyici olmadan onboarding'de "Çok Aktif" seçilince profil UPDATE'i
 * CHECK ihlaliyle başarısız oluyor ve hedefler kaydedilmiyordu.
 * Flutter tarafı enum `.name` gönderdiği için (`veryActive`) aynı sürüşürü —
 * A3 bu ayrıntıyı kendi raporunda ele almalı (bkz. AKTARIM).
 */
const ACTIVITY_LEVEL_TO_DB: Record<ActivityLevel, string> = {
  sedentary: 'sedentary',
  light: 'light',
  moderate: 'moderate',
  active: 'active',
  veryActive: 'very_active',
};

/** UI anahtarı -> veritabanı değeri. Bilinmeyen değerler olduğu gibi geçer. */
export function activityLevelToDb(level: string): string {
  return ACTIVITY_LEVEL_TO_DB[level as ActivityLevel] ?? level;
}

/** Veritabanı değeri -> UI anahtarı. snake_case'i camelCase'e çevirir. */
export function activityLevelFromDb(value: string | null | undefined): ActivityLevel {
  if (!value) return 'moderate';
  return (Object.keys(ACTIVITY_LEVEL_TO_DB) as ActivityLevel[]).find(
    (key) => ACTIVITY_LEVEL_TO_DB[key] === value || key === value,
  ) ?? 'moderate';
}

export const GOALS = {
  lose: { id: 'lose', label: 'Kilo Vermek', calorieModifier: -500 },
  maintain: { id: 'maintain', label: 'Kilo Korumak', calorieModifier: 0 },
  gain: { id: 'gain', label: 'Kilo Almak', calorieModifier: 500 },
} as const;

export type Goal = keyof typeof GOALS;

// Health disclaimer
export const HEALTH_DISCLAIMER = `
Bu uygulama genel bilgilendirme amaçlıdır ve tıbbi tavsiye niteliği taşımaz. 
Beslenme planınız veya kilo hedefiniz için mutlaka bir sağlık uzmanına danışın.
Hesaplanan değerler tahminidir ve kişisel farklılıklara göre değişebilir.
`;
