// CaloriX Constants

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
  fat: 65,
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
