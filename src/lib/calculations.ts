// CaloriX Calculation Functions

import { ACTIVITY_LEVELS, GOALS, type ActivityLevel, type Goal } from './constants';

export interface UserProfile {
  age: number;
  weight: number; // kg
  height: number; // cm
  gender: 'male' | 'female';
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
 * Calculate BMR using Mifflin-St Jeor Equation
 */
export function calculateBMR(profile: Pick<UserProfile, 'weight' | 'height' | 'age' | 'gender'>): number {
  const { weight, height, age, gender } = profile;

  if (gender === 'male') {
    return Math.round(10 * weight + 6.25 * height - 5 * age + 5);
  } else {
    return Math.round(10 * weight + 6.25 * height - 5 * age - 161);
  }
}

/**
 * Calculate TDEE (Total Daily Energy Expenditure)
 */
export function calculateTDEE(bmr: number, activityLevel: ActivityLevel): number {
  const multiplier = ACTIVITY_LEVELS[activityLevel].multiplier;
  return Math.round(bmr * multiplier);
}

/**
 * Calculate target calories based on goal
 */
export function calculateTargetCalories(tdee: number, goal: Goal): number {
  const modifier = GOALS[goal].calorieModifier;
  return Math.max(1200, tdee + modifier); // Minimum 1200 kcal safety
}

/**
 * Calculate macro breakdown from target calories
 * Default split: 30% protein, 40% carbs, 30% fat
 */
export function calculateMacros(
  targetCalories: number,
  proteinPercent = 30,
  carbsPercent = 40,
  fatPercent = 30
): NutritionGoals {
  const proteinCalories = targetCalories * (proteinPercent / 100);
  const carbsCalories = targetCalories * (carbsPercent / 100);
  const fatCalories = targetCalories * (fatPercent / 100);

  return {
    calories: targetCalories,
    protein: Math.round(proteinCalories / 4), // 4 kcal per gram
    carbs: Math.round(carbsCalories / 4), // 4 kcal per gram
    fat: Math.round(fatCalories / 9), // 9 kcal per gram
  };
}

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
 */
export function calculateNutritionForAmount(
  per100g: { kcal: number; protein: number; carbs: number; fat: number },
  amountGrams: number
): { kcal: number; protein: number; carbs: number; fat: number } {
  const multiplier = amountGrams / 100;

  return {
    kcal: Math.round(per100g.kcal * multiplier),
    protein: Math.round(per100g.protein * multiplier * 10) / 10,
    carbs: Math.round(per100g.carbs * multiplier * 10) / 10,
    fat: Math.round(per100g.fat * multiplier * 10) / 10,
  };
}

/**
 * Calculate BMI
 */
export function calculateBMI(weightKg: number, heightCm: number): number {
  // Boy 0 (veya negatif/NaN) → bölme tanımsız: `Infinity`/`NaN` üretip
  // `getBMICategory` tarafında "obez" (Infinity >= 30) olarak sınıflanıyordu,
  // yani **fiziksel olarak imkânsız** bir kayıt yanlış sağlık uyarısı
  // gösteriyordu. Flutter tarafı A3'ün düzelttiği `Calculations.bmi` ile aynı
  // davranış: 0 dön.
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
 * Takvim yılı farkına dayalı yaş — `Index.tsx` kilo kaydı sırasında kullanılır.
 *
 * Önceden `Math.floor((Date.now() - birth) / (365.25 * gün))` kullanılıyordu;
 * bu yaklaşım **duvar saati farkına** duyarlıdır (doğum gününe 1 gün kala
 * 1 gün fazla/eksik sayar) ve 29 Şubat doğumlularda yılda bir gün kaydırır.
 * `OnboardingPage`/`SettingsPage` zaten `calculateAge` kullanıyordu; üç çağrı
 * da aynı hesaba bağlandı (tutarsızlık BMR'yi ~5 kcal kaydırıyordu).
 */
export function calculateAge(birthDate: Date): number {
  if (Number.isNaN(birthDate.getTime())) return 30;
  const now = new Date();
  let age = now.getFullYear() - birthDate.getFullYear();
  const monthDiff = now.getMonth() - birthDate.getMonth();
  // Doğum günü henüz gelmediyse yaş bir azalır.
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < birthDate.getDate())) {
    age -= 1;
  }
  return Math.max(0, age);
}
