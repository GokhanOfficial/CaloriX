import '../constants/app_constants.dart';

/// Beslenme hesaplamaları — web `src/lib/calculations.ts` karşılığı.
/// AI (calculate-macros) başarısız olduğunda yerel fallback olarak kullanılır.
abstract final class Calculations {
  /// Mifflin-St Jeor bazal metabolizma hızı.
  /// `other` cinsiyet web'de olduğu gibi erkek formülüyle hesaplanır.
  static int bmr({
    required double weightKg,
    required double heightCm,
    required int age,
    required Gender gender,
  }) {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    final effective = gender == Gender.female ? base - 161 : base + 5;
    return effective.round();
  }

  /// Günlük toplam enerji harcaması.
  static int tdee(int bmr, ActivityLevel level) =>
      (bmr * level.multiplier).round();

  /// Hedefe göre kalori (minimum 1200 kcal güvenlik sınırı, web ile aynı).
  static int targetCalories(int tdee, Goal goal) {
    final value = tdee + goal.calorieModifier;
    return value < 1200 ? 1200 : value;
  }

  /// Varsayılan makro dağılımı: %30 protein / %40 karb / %30 yağ.
  static ({int protein, int carbs, int fat}) macros(int targetCalories) {
    return (
      protein: ((targetCalories * 0.30) / 4).round(),
      carbs: ((targetCalories * 0.40) / 4).round(),
      fat: ((targetCalories * 0.30) / 9).round(),
    );
  }

  /// Vücut kitle indeksi (1 ondalık).
  static double bmi(double weightKg, double heightCm) {
    final hM = heightCm / 100;
    final raw = weightKg / (hM * hM);
    return (raw * 10).round() / 10;
  }

  /// BMI kategorisi — çeviri anahtarı + renk adı döner (web ile aynı eşikler).
  static ({String labelKey, String color}) bmiCategory(double bmi) {
    if (bmi < 18.5) return (labelKey: 'bmi.underweight', color: 'info');
    if (bmi < 25) return (labelKey: 'bmi.normal', color: 'success');
    if (bmi < 30) return (labelKey: 'bmi.overweight', color: 'warning');
    return (labelKey: 'bmi.obese', color: 'destructive');
  }

  /// Günlük su hedefi (ml) — web: kg * 33.
  static int waterTargetMl(double weightKg) => (weightKg * 33).round();

  /// Yaş hesaplama (doğum günü geçmemişse 1 eksik).
  static int age(DateTime birthDate) {
    final today = DateTime.now();
    var years = today.year - birthDate.year;
    final monthDiff = today.month - birthDate.month;
    if (monthDiff < 0 || (monthDiff == 0 && today.day < birthDate.day)) {
      years--;
    }
    return years;
  }

  /// İlerleme yüzdesi (0-100).
  static int progress(num current, num target) {
    if (target == 0) return 0;
    final pct = ((current / target) * 100).round();
    return pct > 100 ? 100 : pct;
  }
}
