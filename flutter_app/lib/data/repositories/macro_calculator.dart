import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/observability/app_logger.dart';
import '../../core/utils/calculations.dart';
import '../../core/utils/num_parsing.dart';
import '../activity_level_map.dart';
import '../supabase/supabase_client_provider.dart';

/// Onboarding / ayarlar için hesaplanmış günlük hedefler.
class CalculatedGoals {
  const CalculatedGoals({
    required this.bmr,
    required this.tdee,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.bmi,
    required this.waterTarget,
    this.explanation,
    this.usedAi = false,
  });

  final int bmr;
  final int tdee;
  final int calories;
  final int protein;
  final int carbs;
  final int fat;
  final double bmi;
  final int waterTarget;
  final String? explanation;

  /// true ise `calculate-macros` Edge Function, false ise yerel formül.
  final bool usedAi;
}

/// Makro hesaplama — önce AI (`calculate-macros`), hata/eksikte yerel fallback.
/// Web `OnboardingPage.calculateWithAI` akışının birebir karşılığı.
class MacroCalculator {
  MacroCalculator(this._client);

  final SupabaseClient _client;

  Future<CalculatedGoals> calculate({
    required int age,
    required Gender gender,
    required double heightCm,
    required double currentWeightKg,
    required double targetWeightKg,
    required ActivityLevel activityLevel,
    required Goal goal,
    Map<String, dynamic>? previousMacros,
    double? previousWeightKg,
  }) async {
    // Boy 0 / negatif / NaN girdide BMI hesaplanamaz; `CalculatedGoals.bmi`
    // `double` (nullable değil) ve UI'da kategori rengi olarak okunduğu için
    // hesaplanamaz durum 0.0 olarak normalize edilir. Bu değer yalnızca
    // hedef hesabına girmez, fakat `CalculatedGoals` içine yazıldığı için
    // istisna yolu onboarding ekranını düşürürdü. A3 `Calculations.bmi`'yi
    // bölmeyi 0.0'a çevirdi; burada çağrı yeri de kendi payına savunuldu.
    final bmi = _safeBmi(currentWeightKg, heightCm);

    // 1) AI Edge Function dene
    try {
      final res = await _client.functions.invoke(
        'calculate-macros',
        body: {
          'age': age,
          'gender': gender.name,
          'height_cm': heightCm,
          'current_weight_kg': currentWeightKg,
          'target_weight_kg': targetWeightKg,
          // Enum `.name` camelCase (`veryActive`); edge function yalnızca
          // snake_case kabul ediyor → `veryActive` 400 döner ve AI yolu
          // her zaman başarısız olurdu. DB CHECK ile aynı eşleyici.
          'activity_level': activityLevelToDb(activityLevel),
          // `Goal` değerleri (`lose`/`maintain`/`gain`) DB ile birebir aynı;
          // ayrı bir eşleyici gerekmiyor ama sözleşme açık olsun diye
          // `name` yerine açık yazıldı (enum'a yeni değer eklenirse
          // edge function 400 döner ve yerel formüle düşer).
          'goal': goal.name,
          // Kilo güncellemesi akışı (web `Index.tsx` handleWeightSubmit parity).
          // Null değerler JSON'da `null` olarak gider; Edge function bunları
          // güvenle yok sayar (`if (previous_macros && previous_weight_kg)`).
          'previous_macros': previousMacros,
          'previous_weight_kg': previousWeightKg,
        },
      );

      final data = res.data;
      if (res.status == 200 && data is Map<String, dynamic>) {
        // Alan bazlı doğrulama: eksik/NaN bir alan `as num` ile ya istisna
        // fırlatır (tüm onboarding çöker) ya da NaN hedefe dönüşür ve
        // profile yazılır. Bu yüzden tek tek `as num` yerine güvenli
        // okuyucu kullanılır; okunamayan alanlar null sayılır ve
        // doğrulama aşağıda tamamlanır.
        final ai = goalsFromAiBody(data, bmi: bmi, weightKg: currentWeightKg);
        if (ai != null) return ai;

        // 200 dışı, beklenmeyen gövde veya eksik alan → fallback
        AppLog.w(
          'calculate-macros AI yanıtı eksik/geçersiz, yerel formül kullanılıyor',
          {'status': res.status, 'keys': data.keys.toList()},
        );
      }
    } catch (e, s) {
      // Ağ/fonksiyon hatası → yerel hesapla. Sessizce yutulmaz: AI
      // hedeflerinin neden üretilmediği Sentry'ye gider (kullanıcıya
      // hata gösterilmez çünkü yerel fallback her zaman çalışır).
      AppLog.w('calculate-macros edge function hatası, yerel fallback', e, s);
    }

    // 2) Yerel fallback (web ile aynı formüller)
    //    `_safe*` sarmalayıcıları: A3 `Calculations.*` içine sayısal koruma
    //    koydu ama `round()`/`roundToDouble()` çağrıları `NaN`/`Infinity`
    //    girdide hâlâ `UnsupportedError` fırlatabiliyor. Kullanıcı boyu
    //    elle girip `NaN` bırakırsa (boş metin → parse hatası) onboarding
    //    ekranı düşmemeli, hedefler üretilmeli.
    final bmr = _safeBmr(
      weightKg: currentWeightKg.isFinite ? currentWeightKg : 0,
      heightCm: heightCm.isFinite ? heightCm : 0,
      age: age,
      gender: gender,
    );
    final tdee = _safeInt(() => Calculations.tdee(bmr, activityLevel));
    final calories = _safeInt(() => Calculations.targetCalories(tdee, goal));
    final m = Calculations.macros(calories);

    return CalculatedGoals(
      bmr: bmr,
      tdee: tdee,
      calories: calories,
      protein: m.protein,
      carbs: m.carbs,
      fat: m.fat,
      bmi: bmi,
      waterTarget: _safeInt(
        () => Calculations.waterTargetMl(currentWeightKg),
      ),
    );
  }

  /// AI (`calculate-macros`) yanıt gövdesini doğrulanmış hedeflere çevirir.
  ///
  /// Zorunlu alanlardan biri eksik, yanlış tipli (`String`) veya sonlu değilse
  /// (`NaN`/`Infinity`) **null** döner; çağıran yerel formüle düşer. Böylece
  /// ne onboarding ekranı istisnayla düşer ne de profile `NaN` hedef yazılır.
  static CalculatedGoals? goalsFromAiBody(
    Map<String, dynamic> data, {
    required double bmi,
    required double weightKg,
  }) {
    final bmr = numOrNull(data['bmr']);
    final tdee = numOrNull(data['tdee']);
    final calories = numOrNull(data['daily_calorie_target']);
    final protein = numOrNull(data['protein_target_g']);
    final carbs = numOrNull(data['carbs_target_g']);
    final fat = numOrNull(data['fat_target_g']);
    final water = numOrNull(data['daily_water_target_ml']);

    if (bmr == null ||
        tdee == null ||
        calories == null ||
        protein == null ||
        carbs == null ||
        fat == null) {
      return null;
    }

    return CalculatedGoals(
      bmr: bmr.round(),
      tdee: tdee.round(),
      calories: calories.round(),
      protein: protein.round(),
      carbs: carbs.round(),
      fat: fat.round(),
      bmi: bmi,
      // Su hedefi AI'dan gelmezse yerel formül (kg * 33).
      waterTarget: (water ?? Calculations.waterTargetMl(weightKg)).round(),
      explanation: data['explanation'] as String?,
      usedAi: true,
    );
  }
}

/// BMI hesabını iki taraftan savunur: `Calculations.bmi` zaten bölme
/// tanımsızlığında 0 döndürüyor, ancak girdiler `NaN`/`Infinity` ise
/// `roundToDouble()` istisnası fırlatabilir. Hedefler hesaplanabilir
/// kalmalı; BMI yalnızca ekranda kategori olarak okunuyor.
double _safeBmi(double weightKg, double heightCm) {
  if (!weightKg.isFinite || !heightCm.isFinite) {
    AppLog.w(
      'BMI girdisi sonlu değil, 0 kullanılıyor',
      {'weight': weightKg, 'height': heightCm},
    );
    return 0;
  }
  try {
    final bmi = Calculations.bmi(weightKg, heightCm);
    return bmi.isFinite ? bmi : 0;
  } catch (e, s) {
    AppLog.w('BMI hesaplanamadı, 0 kullanılıyor', e, s);
    return 0;
  }
}

/// BMR hesabı — `round()` `NaN`/`Infinity` girdide `UnsupportedError` fırlatır.
int _safeBmr({
  required double weightKg,
  required double heightCm,
  required int age,
  required Gender gender,
}) {
  if (!weightKg.isFinite || !heightCm.isFinite) {
    AppLog.w(
      'BMR girdisi sonlu değil, minimum kullanılıyor',
      {'weight': weightKg, 'height': heightCm},
    );
    return Calculations.minBmr;
  }
  return _safeInt(
    () => Calculations.bmr(
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
    ),
  );
}

/// `int` üreten hesabı istisna/NaN'dan korur; düşerse mantıklı bir taban
/// değere döner ve **sessizce yutmaz** (Sentry'ye gider).
int _safeInt(int Function() compute, {int fallback = 0}) {
  try {
    return compute();
  } catch (e, s) {
    AppLog.w('Makro hesabı başarısız, taban değer kullanılıyor', e, s);
    return fallback;
  }
}

final macroCalculatorProvider = Provider<MacroCalculator>((ref) {
  return MacroCalculator(ref.watch(supabaseClientProvider));
});
