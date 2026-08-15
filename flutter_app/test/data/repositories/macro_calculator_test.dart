import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/utils/calculations.dart';
import 'package:calorix/data/repositories/macro_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

Future<CalculatedGoals> _call(MacroCalculator calc) => calc.calculate(
      age: 30,
      gender: Gender.male,
      heightCm: 180,
      currentWeightKg: 80,
      targetWeightKg: 75,
      activityLevel: ActivityLevel.moderate,
      goal: Goal.lose,
    );

void main() {
  late MockSupabaseClient client;
  late MockFunctionsClient functions;
  late MacroCalculator calc;

  setUp(() {
    client = MockSupabaseClient();
    functions = MockFunctionsClient();
    when(() => client.functions).thenReturn(functions);
    calc = MacroCalculator(client);
  });

  group('MacroCalculator — AI başarılı', () {
    test('200 + geçerli gövde: Edge Function değerleri kullanılır', () async {
      when(() => functions.invoke('calculate-macros', body: any(named: 'body')))
          .thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: <String, dynamic>{
            'bmr': 1780.0,
            'tdee': 2759.0,
            'daily_calorie_target': 2259.0,
            'protein_target_g': 170.0,
            'carbs_target_g': 226.0,
            'fat_target_g': 75.0,
            'daily_water_target_ml': 2640.0,
            'explanation': 'Test açıklaması',
          },
        ),
      );

      final goals = await _call(calc);

      expect(goals.usedAi, isTrue);
      expect(goals.bmr, 1780);
      expect(goals.tdee, 2759);
      expect(goals.calories, 2259);
      expect(goals.protein, 170);
      expect(goals.carbs, 226);
      expect(goals.fat, 75);
      expect(goals.waterTarget, 2640);
      expect(goals.explanation, 'Test açıklaması');
      // BMI her zaman yerel hesaplanır
      expect(goals.bmi, Calculations.bmi(80, 180));
    });

    test('istek gövdesi web ile aynı alan adlarını taşır', () async {
      Object? capturedBody;
      when(() => functions.invoke('calculate-macros', body: any(named: 'body')))
          .thenAnswer((inv) async {
        capturedBody = inv.namedArguments[#body];
        return FunctionResponse(status: 200, data: <String, dynamic>{
          'bmr': 1, 'tdee': 1, 'daily_calorie_target': 1200,
          'protein_target_g': 1, 'carbs_target_g': 1, 'fat_target_g': 1,
          'daily_water_target_ml': 1,
        });
      });

      await _call(calc);

      final body = capturedBody! as Map<String, dynamic>;
      expect(body, containsPair('age', 30));
      expect(body, containsPair('gender', 'male'));
      expect(body, containsPair('height_cm', 180.0));
      expect(body, containsPair('current_weight_kg', 80.0));
      expect(body, containsPair('target_weight_kg', 75.0));
      expect(body, containsPair('activity_level', 'moderate'));
      expect(body, containsPair('goal', 'lose'));
    });
  });

  group('MacroCalculator — yerel fallback', () {
    test('fonksiyon hata fırlatırsa yerel formül kullanılır', () async {
      when(() => functions.invoke('calculate-macros', body: any(named: 'body')))
          .thenThrow(Exception('network down'));

      final goals = await _call(calc);

      expect(goals.usedAi, isFalse);
      expect(goals.explanation, isNull);
      // Elle hesap: bmr=1780, tdee=1780*1.55=2759, lose=2259
      expect(goals.bmr, 1780);
      expect(goals.tdee, 2759);
      expect(goals.calories, 2259);
      expect(goals.waterTarget, 2640); // 80*33
      final m = Calculations.macros(2259);
      expect(goals.protein, m.protein);
      expect(goals.carbs, m.carbs);
      expect(goals.fat, m.fat);
    });

    test('200 dışı status → fallback', () async {
      when(() => functions.invoke('calculate-macros', body: any(named: 'body')))
          .thenAnswer(
        (_) async => FunctionResponse(status: 500, data: 'Server error'),
      );

      final goals = await _call(calc);

      expect(goals.usedAi, isFalse);
      expect(goals.bmr, 1780);
    });

    test('gövde Map değilse → fallback', () async {
      when(() => functions.invoke('calculate-macros', body: any(named: 'body')))
          .thenAnswer((_) async => FunctionResponse(status: 200, data: 'ok'));

      final goals = await _call(calc);

      expect(goals.usedAi, isFalse);
    });
  });
}
