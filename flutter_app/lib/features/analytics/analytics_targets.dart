import '../../../core/constants/app_constants.dart';
import '../../../data/models/profile.dart';

/// Hedefler — profilden, yoksa web `DEFAULT_GOALS` değerleri.
///
/// Tüm analitik kartları aynı hedef kümesini kullanır; bu yüzden ayrı bir
/// dosyada yaşar ve `part`/gizli isim yerine **normal import** ile
/// paylaşılır. `analytics_page.dart` 1239 satırdı (Tur 6'da bölündü):
/// buraya taşınan türler hedef **verisi**, kartlar ise **görselleştirme**
/// sorumluluğudur — bu ayrım kartların bağımsız test edilmesini sağlar.
class AnalyticsTargets {
  const AnalyticsTargets({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.water,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double water;

  factory AnalyticsTargets.fromProfile(Profile? p) => AnalyticsTargets(
        calories:
            (p?.dailyCalorieTarget ?? AppConstants.defaultCalories).toDouble(),
        protein: (p?.proteinTargetG ?? AppConstants.defaultProtein).toDouble(),
        carbs: (p?.carbsTargetG ?? AppConstants.defaultCarbs).toDouble(),
        fat: (p?.fatTargetG ?? AppConstants.defaultFat).toDouble(),
        water: (p?.dailyWaterTargetMl ?? AppConstants.defaultWater).toDouble(),
      );
}

/// Hedef yüzdesi — hedef 0/NaN/negatifse 0 (sıfıra bölme koruması).
///
/// Profil satırı bozuk olduğunda (`daily_calorie_target = 0` ya da NaN) bu
/// yardımcı olmadan `value / 0` üretir: Dart'ta `Infinity.round()`
/// **istisna fırlatır** (`UnsupportedError`) ve istatistik ızgarasının
/// tamamı çöker. A4 (Tur 1) bu noktada 5 ayrı yerel çözüm bulmuştu; tek
/// fonksiyonla birleştirildi.
int analyticsPercent(num value, num target) {
  if (target <= 0 || target.isNaN) return 0;
  return (value / target * 100).round();
}
