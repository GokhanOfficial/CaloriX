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
    if (!effective.isFinite) return minBmr;
    return effective.round().clamp(minBmr, 1 << 31);
  }

  /// Günlük toplam enerji harcaması.
  ///
  /// `bmr` zaten `minBmr` (0) altına kırpıldığı için sonuç negatif olamaz;
  /// yine de `isFinite` koruması `Int` taşması (çok büyük profil) ve
  /// `round()`'ın `UnsupportedError` fırlatması ihtimaline karşı durur.
  static int tdee(int bmr, ActivityLevel level) {
    if (bmr <= minBmr) return minBmr;
    final value = (bmr * level.multiplier).round();
    return value < minBmr ? minBmr : value;
  }

  /// Hedefe göre kalori (minimum 1200 kcal güvenlik sınırı, web ile aynı).
  static int targetCalories(int tdee, Goal goal) {
    final value = tdee + goal.calorieModifier;
    return value < 1200 ? 1200 : value;
  }

  /// Varsayılan makro dağılımı: %30 protein / %40 karb / %30 yağ.
  ///
  /// Negatif (veya 0) kalori hedefi üç makroda negatif değer üretirdi; hedef
  /// zaten `targetCalories` ile ≥1200'e çekildiği için burada da alt sınır
  /// uygulanır. Web parity'si nominal pozitif girdilerde bozulmaz.
  static ({int protein, int carbs, int fat}) macros(int targetCalories) {
    if (targetCalories <= 0) return (protein: 0, carbs: 0, fat: 0);
    // Oranlar **tek yerde** tanımlı; `tool/check_versions.cjs` bu sabitleri
    // web `calculateMacros` varsayılanlarıyla (`proteinPercent = 30` vb.)
    // karşılaştırıyor. Değerler burada değiştirilirse web tarafı
    // `src/lib/calculations.ts` ile birlikte güncellenmelidir.
    return (
      protein: ((targetCalories * proteinRatio) / proteinKcalPerG).round(),
      carbs: ((targetCalories * carbsRatio) / carbsKcalPerG).round(),
      fat: ((targetCalories * fatRatio) / fatKcalPerG).round(),
    );
  }

  /// Makro dağılım oranları (toplam 1.0) — web `calculateMacros` ile aynı.
  static const double proteinRatio = 0.30;
  static const double carbsRatio = 0.40;
  static const double fatRatio = 0.30;

  /// Gram başına kalori (atwater) — fizyolojik sabit.
  static const int proteinKcalPerG = 4;
  static const int carbsKcalPerG = 4;
  static const int fatKcalPerG = 9;

  /// Vücut kitle indeksi (1 ondalık).
  ///
  /// Boy 0 (veya NaN) ise bölme tanımsız; `UnsupportedError` fırlatmak yerine
  /// `0` döner — çağıran taraf (`MacroCalculator.calculate`) bu değeri
  /// `try` bloğu DIŞINDA kullandığı için istisna akışı kırıp ekranı düşürüyordu.
  /// Böyle bir kayıt fiziksel olarak da geçersizdir; 0.0 = "hesaplanamadı".
  ///
  /// ## ⭐ Neden **kilo** de `> 0` olmalı? (A2r9, `check_versions.cjs` bulgusu)
  ///
  /// A3r6 boy tarafını düzeltti ama ağırlıkta yalnızca `isFinite` kontrolü
  /// kaldı. BMI formülünde boy **kare** olduğu için `bmi(70, -180) = 24.2`
  /// döner — yani **fiziksel olarak imkânsız** bir kayıt (70 kg / −180 cm)
  /// geçerli bir "normal" BMI olarak üretilir ve `bmiCategory` bunu
  /// `bmi.normal` etiketiyle yeşil gösterir. Negatif kilo/BMI'yi
  /// `bmi.underweight` (<18.5) olarak göstermekten daha kötüdür: kullanıcı
  /// **doğru** görünen ama **temelsiz** bir sayı görür.
  ///
  /// Web sözleşmesi (`src/lib/calculations.ts:294`) **kilo ≤ 0 → 0** diyor;
  /// iki istemci aynı kaydı farklı değerlendirmemeli. `tool/check_versions.cjs`
  /// bu ayrışmayı ikili bir kapı olarak denetler — düzeltme sonrası
  /// "BMI ağırlık alt sınırı iki tarafta farklı" uyarısı düşer.
  static double bmi(double weightKg, double heightCm) {
    if (!heightCm.isFinite || heightCm <= 0) return 0;
    if (!weightKg.isFinite || weightKg <= 0) return 0;
    final hM = heightCm / 100;
    final raw = weightKg / (hM * hM);
    if (!raw.isFinite) return 0;
    return (raw * 10).roundToDouble() / 10;
  }

  /// BMI kategorisi — çeviri anahtarı + renk adı döner (web ile aynı eşikler).
  static ({String labelKey, String color}) bmiCategory(double bmi) {
    if (bmi < 18.5) return (labelKey: 'bmi.underweight', color: 'info');
    if (bmi < 25) return (labelKey: 'bmi.normal', color: 'success');
    if (bmi < 30) return (labelKey: 'bmi.overweight', color: 'warning');
    return (labelKey: 'bmi.obese', color: 'destructive');
  }

  /// Günlük su hedefi (ml) — web: kg * 33.
  ///
  /// `NaN`/`Infinity` kilo girdisinde `round()` `UnsupportedError` fırlatıyordu.
  /// Çağıranlar (`MacroCalculator`) zaten sonlu olmayan kilo nedeniyle
  /// 0 bekliyor; burada aynı sözleşme açıkça uygulanır.
  static int waterTargetMl(double weightKg) {
    if (!weightKg.isFinite) return 0;
    final value = (weightKg * 33).round();
    return value < 0 ? 0 : value;
  }

  /// Yaş hesaplama (doğum günü geçmemişse 1 eksik).
  ///
  /// Gelecek bir doğum tarihi veya 120 yaş üstü kayıt geçersizdir; negatif
  /// yaş BMR'ı çarpık değerlere sürükler. Sonuç `0..120` aralığına kırpılır.
  static int age(DateTime birthDate) {
    final today = DateTime.now();
    var years = today.year - birthDate.year;
    final monthDiff = today.month - birthDate.month;
    if (monthDiff < 0 || (monthDiff == 0 && today.day < birthDate.day)) {
      years--;
    }
    if (years < 0) return 0;
    if (years > maxAge) return maxAge;
    return years;
  }

  /// BMR/target hesaplarında kabul edilen üst yaş sınırı.
  static const int maxAge = 120;

  /// BMR için alt sınır: 0'ın altındaki BMR fiziksel olarak anlamsızdır ve
  /// TDEE/hedef hesaplarını yanlış yönde çeker.
  static const int minBmr = 0;

  /// İlerleme yüzdesi (0-100).
  ///
  /// Üç savunma katmanı:
  ///  * sıfır/negatif hedef → 0 (bölme tanımsız; ayrıca bölme işareti),
  ///  * `NaN`/`Infinity` girdi → 0. `round()` bu değerlerde
  ///    `UnsupportedError` fırlatıyordu; hedefi bozuk bir öğün ekranı
  ///    düşürüyordu (`macro_calculator.dart` bunu `_safeInt` ile sarıyordu,
  ///    diğer çağıranlar sarıyordu),
  ///  * negatif tüketim / hedef aşımı → 0..100 aralığı.
  static int progress(num current, num target) {
    if (!target.isFinite || target == 0) return 0;
    if (!current.isFinite) return 0;
    final pct = ((current / target) * 100).round();
    if (pct < 0) return 0;
    return pct > 100 ? 100 : pct;
  }
}
