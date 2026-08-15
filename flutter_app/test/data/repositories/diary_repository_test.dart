import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/models/food_item.dart';
import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/models/water_entry.dart';
import 'package:calorix/data/models/weight_entry.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// DiaryRepository'nin saf (Supabase'siz) kısımları:
/// gün formatı, öğün gruplama, toplam hesapları, 100g→miktar dönüşümü.
///
/// Web parity referansları: `useDailyData.ts` (totals/mealsByType/totalWater),
/// `AddFromFoodDialog.tsx` (forAmount formülleri).
void main() {
  group('formatEntryDate', () {
    test('yyyy-MM-dd formatında, tek haneli ay/gün sıfır dolgulu', () {
      expect(formatEntryDate(DateTime(2026, 8, 15)), '2026-08-15');
      expect(formatEntryDate(DateTime(2026, 1, 5)), '2026-01-05');
      expect(formatEntryDate(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    });
  });

  group('DailyData.mealsByType', () {
    MealEntry entry(String id, String mealType) => MealEntry(
          id: id,
          userId: 'u1',
          mealType: mealType,
          amountGMl: 100,
          calculatedKcal: 0,
          calculatedProtein: 0,
          calculatedCarbs: 0,
          calculatedFat: 0,
          entryDate: '2026-08-15',
          source: 'manual',
          createdAt: '2026-08-15T08:00:00Z',
        );

    test('girdileri öğün tipine göre gruplar', () {
      final data = DailyData(
        mealEntries: [
          entry('1', 'breakfast'),
          entry('2', 'lunch'),
          entry('3', 'breakfast'),
          entry('4', 'snack'),
        ],
        waterEntries: const [],
      );

      expect(data.mealsByType[MealType.breakfast]!.map((e) => e.id),
          ['1', '3']);
      expect(data.mealsByType[MealType.lunch]!.single.id, '2');
      expect(data.mealsByType[MealType.snack]!.single.id, '4');
      expect(data.mealsByType[MealType.dinner], isNull);
    });

    test('bilinmeyen meal_type atlanır (enum dışı)', () {
      final data = DailyData(
        mealEntries: [entry('x', 'brunch')],
        waterEntries: const [],
      );
      expect(data.mealsByType, isEmpty);
    });

    test('boş listede boş map', () {
      expect(DailyData.empty.mealsByType, isEmpty);
    });
  });

  group('DailyData.totals', () {
    MealEntry entry({
      required double kcal,
      required double p,
      required double c,
      required double f,
    }) =>
        MealEntry(
          id: 'x',
          userId: 'u1',
          mealType: 'lunch',
          amountGMl: 100,
          calculatedKcal: kcal,
          calculatedProtein: p,
          calculatedCarbs: c,
          calculatedFat: f,
          entryDate: '2026-08-15',
          source: 'manual',
          createdAt: '2026-08-15T08:00:00Z',
        );

    test('calculated_* alanlarının toplamı (web totals reduce parity)', () {
      final data = DailyData(
        mealEntries: [
          entry(kcal: 500, p: 30, c: 50, f: 20),
          entry(kcal: 250.5, p: 10.5, c: 25.25, f: 5),
        ],
        waterEntries: const [],
      );

      expect(data.totals.calories, 750.5);
      expect(data.totals.protein, 40.5);
      expect(data.totals.carbs, 75.25);
      expect(data.totals.fat, 25.0);
    });

    test('boş listede sıfır', () {
      expect(DailyData.empty.totals,
          (calories: 0.0, protein: 0.0, carbs: 0.0, fat: 0.0));
    });
  });

  group('DailyData.totalWater', () {
    WaterEntry water(double ml) => WaterEntry(
          id: 'w',
          userId: 'u1',
          amountMl: ml,
          entryDate: '2026-08-15',
        );

    test('amount_ml toplamı', () {
      final data = DailyData(
        mealEntries: const [],
        waterEntries: [water(250), water(500), water(250)],
      );
      expect(data.totalWater, 1000);
    });

    test('boş listede sıfır', () {
      expect(DailyData.empty.totalWater, 0);
    });
  });

  group('DailyData.latestWeight', () {
    test('opsiyonel — null kalabilir (gün filtresiz son kayıt)', () {
      const weight = WeightEntry(
        id: 'w1',
        userId: 'u1',
        weightKg: 82.5,
        entryDate: '2026-08-01',
      );
      final data = DailyData(
        mealEntries: const [],
        waterEntries: const [],
        latestWeight: weight,
      );
      expect(data.latestWeight!.weightKg, 82.5);
      expect(DailyData.empty.latestWeight, isNull);
    });
  });

  group('FoodItem.forAmount', () {
    const food = FoodItem(
      id: 'f1',
      name: 'Tavuk Göğsü',
      calories: 165,
      proteinG: 31,
      carbsG: 0,
      fatG: 3.6,
    );

    test('100g için aynen döner', () {
      final calc = food.forAmount(100);
      expect(calc.kcal, 165);
      expect(calc.protein, 31);
      expect(calc.carbs, 0);
      expect(calc.fat, 3.6);
    });

    test('miktarla orantılı — kcal round, makrolar 1 ondalık (web parity)',
        () {
      final calc = food.forAmount(150);
      expect(calc.kcal, 248); // 165 * 1.5 = 247.5 → round 248
      expect(calc.protein, 46.5);
      expect(calc.carbs, 0);
      expect(calc.fat, 5.4); // 3.6 * 1.5 = 5.4
    });

    test('küsüratlı makro 1 ondalığa yuvarlanır', () {
      const tricky = FoodItem(
        id: 'f2',
        name: 'X',
        calories: 133,
        proteinG: 7.77,
        carbsG: 0.35,
        fatG: 1.05,
      );
      final calc = tricky.forAmount(33);
      expect(calc.kcal, 44); // 43.89 → 44
      expect(calc.protein, 2.6); // 2.5641 → 2.6
      expect(calc.carbs, 0.1); // 0.1155 → 0.1
      expect(calc.fat, 0.3); // 0.3465 → 0.3
    });
  });
}
