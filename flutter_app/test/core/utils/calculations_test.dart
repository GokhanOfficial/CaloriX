import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/utils/calculations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Web `src/lib/calculations.ts` ile birebir parity testleri.
/// Referans değerler web formüllerinden elle hesaplanmıştır.
void main() {
  group('Calculations.bmr (Mifflin-St Jeor)', () {
    test('erkek: 10w + 6.25h - 5a + 5', () {
      // 80kg, 180cm, 30y -> 800 + 1125 - 150 + 5 = 1780
      final bmr = Calculations.bmr(
        weightKg: 80,
        heightCm: 180,
        age: 30,
        gender: Gender.male,
      );
      expect(bmr, 1780);
    });

    test('kadın: 10w + 6.25h - 5a - 161', () {
      // 60kg, 165cm, 25y -> 600 + 1031.25 - 125 - 161 = 1345.25 -> 1345
      final bmr = Calculations.bmr(
        weightKg: 60,
        heightCm: 165,
        age: 25,
        gender: Gender.female,
      );
      expect(bmr, 1345);
    });

    test('other cinsiyet erkek formülüyle hesaplanır (web parity)', () {
      final male = Calculations.bmr(
        weightKg: 70,
        heightCm: 175,
        age: 40,
        gender: Gender.male,
      );
      final other = Calculations.bmr(
        weightKg: 70,
        heightCm: 175,
        age: 40,
        gender: Gender.other,
      );
      expect(other, male);
    });
  });

  group('Calculations.tdee', () {
    test('her aktivite seviyesi doğru çarpanı kullanır', () {
      const bmr = 2000;
      expect(Calculations.tdee(bmr, ActivityLevel.sedentary), 2400);
      expect(Calculations.tdee(bmr, ActivityLevel.light), 2750);
      expect(Calculations.tdee(bmr, ActivityLevel.moderate), 3100);
      expect(Calculations.tdee(bmr, ActivityLevel.active), 3450);
      expect(Calculations.tdee(bmr, ActivityLevel.veryActive), 3800);
    });
  });

  group('Calculations.targetCalories', () {
    test('lose: -500, maintain: 0, gain: +500', () {
      const tdee = 2500;
      expect(Calculations.targetCalories(tdee, Goal.lose), 2000);
      expect(Calculations.targetCalories(tdee, Goal.maintain), 2500);
      expect(Calculations.targetCalories(tdee, Goal.gain), 3000);
    });

    test('1200 kcal altına düşmez (güvenlik sınırı)', () {
      // 1400 TDEE - 500 = 900 -> 1200
      expect(Calculations.targetCalories(1400, Goal.lose), 1200);
    });
  });

  group('Calculations.macros (30/40/30)', () {
    test('2000 kcal: P150 C200 Y67', () {
      final m = Calculations.macros(2000);
      expect(m.protein, 150); // 2000*0.30/4
      expect(m.carbs, 200); // 2000*0.40/4
      expect(m.fat, 67); // 2000*0.30/9 = 66.67
    });

    test('0 kcal verilirse 0 döner', () {
      final m = Calculations.macros(0);
      expect(m.protein, 0);
      expect(m.carbs, 0);
      expect(m.fat, 0);
    });
  });

  group('Calculations.bmi', () {
    test('standart örnek', () {
      // 70kg / 1.75^2 = 22.857 -> 22.9
      expect(Calculations.bmi(70, 175), 22.9);
    });

    test('1 ondalık basamağa yuvarlar', () {
      // 80kg / 1.8^2 = 24.691 -> 24.7
      expect(Calculations.bmi(80, 180), 24.7);
    });
  });

  group('Calculations.bmiCategory', () {
    test('eşikler: 18.5 / 25 / 30', () {
      expect(Calculations.bmiCategory(18.4).labelKey, 'bmi.underweight');
      expect(Calculations.bmiCategory(18.5).labelKey, 'bmi.normal');
      expect(Calculations.bmiCategory(24.9).labelKey, 'bmi.normal');
      expect(Calculations.bmiCategory(25.0).labelKey, 'bmi.overweight');
      expect(Calculations.bmiCategory(29.9).labelKey, 'bmi.overweight');
      expect(Calculations.bmiCategory(30.0).labelKey, 'bmi.obese');
    });
  });

  group('Calculations.waterTargetMl', () {
    test('kg * 33', () {
      expect(Calculations.waterTargetMl(70), 2310);
      expect(Calculations.waterTargetMl(80.5), 2657); // 2656.5 -> round
    });
  });

  group('Calculations.progress', () {
    test('yüzde ve 100 sınırı', () {
      expect(Calculations.progress(500, 2000), 25);
      expect(Calculations.progress(2500, 2000), 100);
      expect(Calculations.progress(100, 0), 0);
    });
  });

  group('Calculations.age', () {
    test('doğum günü geçmemişse 1 eksik', () {
      final now = DateTime.now();
      final turned = DateTime(now.year - 30, now.month, now.day);
      expect(Calculations.age(turned), 30);

      final notYet = now.month == 12
          ? DateTime(now.year - 30, now.month, now.day + 1)
          : DateTime(now.year - 31, now.month + 1, now.day);
      expect(Calculations.age(notYet), 30);
    });
  });
}
