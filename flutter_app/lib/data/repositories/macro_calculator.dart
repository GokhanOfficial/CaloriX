import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/calculations.dart';
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
    final bmi = Calculations.bmi(currentWeightKg, heightCm);

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
          'activity_level': activityLevel.name,
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
        return CalculatedGoals(
          bmr: (data['bmr'] as num).round(),
          tdee: (data['tdee'] as num).round(),
          calories: (data['daily_calorie_target'] as num).round(),
          protein: (data['protein_target_g'] as num).round(),
          carbs: (data['carbs_target_g'] as num).round(),
          fat: (data['fat_target_g'] as num).round(),
          bmi: bmi,
          waterTarget: (data['daily_water_target_ml'] as num).round(),
          explanation: data['explanation'] as String?,
          usedAi: true,
        );
      }
      // 200 dışı veya beklenmeyen gövde → fallback
    } catch (_) {
      // Ağ/fonksiyon hatası → yerel hesapla
    }

    // 2) Yerel fallback (web ile aynı formüller)
    final bmr = Calculations.bmr(
      weightKg: currentWeightKg,
      heightCm: heightCm,
      age: age,
      gender: gender,
    );
    final tdee = Calculations.tdee(bmr, activityLevel);
    final calories = Calculations.targetCalories(tdee, goal);
    final m = Calculations.macros(calories);

    return CalculatedGoals(
      bmr: bmr,
      tdee: tdee,
      calories: calories,
      protein: m.protein,
      carbs: m.carbs,
      fat: m.fat,
      bmi: bmi,
      waterTarget: Calculations.waterTargetMl(currentWeightKg),
    );
  }
}

final macroCalculatorProvider = Provider<MacroCalculator>((ref) {
  return MacroCalculator(ref.watch(supabaseClientProvider));
});
