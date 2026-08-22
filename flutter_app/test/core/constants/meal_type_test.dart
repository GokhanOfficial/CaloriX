import 'package:calorix/core/constants/app_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faz 2 — FAB/öğün kartı "+" için zaman-tabanlı varsayılan öğün çekirdeği.
/// `MealType.defaultForNow` bunu `DateTime.now().hour` ile çağırır; eşikler
/// burada deterministik doğrulanır.
void main() {
  group('MealType.defaultMealForHour', () {
    test('sabah (hour < 11) → breakfast', () {
      expect(MealType.defaultMealForHour(0), MealType.breakfast);
      expect(MealType.defaultMealForHour(7), MealType.breakfast);
      expect(MealType.defaultMealForHour(10), MealType.breakfast);
    });

    test('öğle (11 ≤ hour < 16) → lunch', () {
      expect(MealType.defaultMealForHour(11), MealType.lunch);
      expect(MealType.defaultMealForHour(12), MealType.lunch);
      expect(MealType.defaultMealForHour(15), MealType.lunch);
    });

    test('akşam (16 ≤ hour < 21) → dinner', () {
      expect(MealType.defaultMealForHour(16), MealType.dinner);
      expect(MealType.defaultMealForHour(18), MealType.dinner);
      expect(MealType.defaultMealForHour(20), MealType.dinner);
    });

    test('gece (hour ≥ 21) → snack', () {
      expect(MealType.defaultMealForHour(21), MealType.snack);
      expect(MealType.defaultMealForHour(23), MealType.snack);
    });

    test('eşik sınırları doğru taraf', () {
      // 11 → lunch (breakfast değil), 16 → dinner (lunch değil),
      // 21 → snack (dinner değil).
      expect(MealType.defaultMealForHour(10), MealType.breakfast);
      expect(MealType.defaultMealForHour(11), MealType.lunch);
      expect(MealType.defaultMealForHour(15), MealType.lunch);
      expect(MealType.defaultMealForHour(16), MealType.dinner);
      expect(MealType.defaultMealForHour(20), MealType.dinner);
      expect(MealType.defaultMealForHour(21), MealType.snack);
    });
  });

  group('MealType.defaultForNow', () {
    test('geçerli bir MealType döner', () {
      // Şu anki saate göre biri dönmeli; enum dışı değil.
      expect(MealType.values, contains(MealType.defaultForNow()));
    });
  });
}
