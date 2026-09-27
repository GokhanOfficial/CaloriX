import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/utils/calculations.dart';
import 'package:calorix/data/repositories/analytics_repository.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/data/repositories/food_repository.dart';
import 'package:calorix/data/repositories/macro_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// `lib/data/**` yazma sınırlarının (data guard) birim testleri.
///
/// Kapsam — bu dosya **hiçbir ağ çağrısı yapmaz**; yalnızca veri katmanının
/// saf/validasyon parçalarını doğrular:
///
/// 1. `DiaryRepository` yazma doğrulaması: NaN / Infinity / negatif / sıfır
///    miktar ve makro değerleri DB'ye gitmeden `ArgumentError` ile reddedilir.
/// 2. `FoodRepository._customItem` 100g normalizasyonu: `amount_g_ml` 0/negatif/
///    null iken `x/0 → Infinity → round()` istisnası yerine güvenli değer.
/// 3. `MacroCalculator` AI gövdesi doğrulaması: eksik alan / string / NaN
///    gövde sessizce NaN hedefe dönüşmez, yerel formüle düşer.
/// 4. `AnalyticsRepository` takvim günü aritmetiği: DST'de gün atlanmaz /
///    fazlanmaz; bozuk satır tüm seriyi düşürmez.
///
/// Web parity referansları: `src/lib/calculations.ts`, `useAnalyticsData.ts`.
void main() {
  group('1) DiaryRepository — yazma sınırı doğrulaması', () {
    late _MockSupabaseClient client;
    late DiaryRepository repo;

    // `insert` zincirine hiç ulaşılmaması gereken durumları doğrulamak için
    // `from(...)` çağrısı bir "canlı tel" olarak kurulur: zincirin sonuna
    // gelinirse test `StateError` ile düşer (sessiz geçiş olmaz).
    setUp(() {
      client = _MockSupabaseClient();
      repo = DiaryRepository(client);
    });

    void forbidDb() {
      when(() => client.from(any())).thenThrow(
        StateError('değer doğrulaması DB çağrısından ÖNCE yapılmalıydı'),
      );
    }

    test('addMealEntry: NaN miktar reddedilir, insert çağrılmaz', () {
      forbidDb();
      expect(
        () => repo.addMealEntry(
          'u1',
          mealType: MealType.breakfast.name,
          amountGMl: double.nan,
          calculatedKcal: 100,
          calculatedProtein: 10,
          calculatedCarbs: 10,
          calculatedFat: 5,
          entryDate: '2026-08-15',
        ),
        throwsArgumentError,
      );
    });

    test('addMealEntry: Infinity makro değeri reddedilir', () {
      forbidDb();
      expect(
        () => repo.addMealEntry(
          'u1',
          mealType: MealType.lunch.name,
          amountGMl: 100,
          calculatedKcal: double.infinity,
          calculatedProtein: 10,
          calculatedCarbs: 10,
          calculatedFat: 5,
          entryDate: '2026-08-15',
        ),
        throwsArgumentError,
      );
    });

    test('addMealEntry: negatif kcal reddedilir (toplamları bozmaz)', () {
      forbidDb();
      expect(
        () => repo.addMealEntry(
          'u1',
          mealType: MealType.dinner.name,
          amountGMl: 100,
          calculatedKcal: -50,
          calculatedProtein: 10,
          calculatedCarbs: 10,
          calculatedFat: 5,
          entryDate: '2026-08-15',
        ),
        throwsArgumentError,
      );
    });

    test('addMealEntry: 0 miktar reddedilir (100g normalizasyonu bölmesi)', () {
      forbidDb();
      expect(
        () => repo.addMealEntry(
          'u1',
          mealType: MealType.snack.name,
          amountGMl: 0,
          calculatedKcal: 100,
          calculatedProtein: 10,
          calculatedCarbs: 10,
          calculatedFat: 5,
          entryDate: '2026-08-15',
        ),
        throwsArgumentError,
      );
    });

    test('addWeightEntry: 0 / negatif / NaN kilo reddedilir', () {
      forbidDb();
      for (final bad in <double>[0, -70, double.nan, double.infinity]) {
        expect(
          () => repo.addWeightEntry('u1', weightKg: bad, entryDate: '2026-08-15'),
          throwsArgumentError,
          reason: 'weightKg=$bad yazılmamalı',
        );
      }
    });

    test('addWaterEntry: 0 / negatif ml reddedilir', () {
      forbidDb();
      for (final bad in <double>[0, -250, double.nan]) {
        expect(
          () => repo.addWaterEntry('u1', amountMl: bad, entryDate: '2026-08-15'),
          throwsArgumentError,
          reason: 'amountMl=$bad yazılmamalı',
        );
      }
    });

    test('updateMealEntry: kısmi güncellemede 0 miktar reddedilir', () {
      forbidDb();
      expect(
        () => repo.updateMealEntry('u1', 'm1', {'amount_g_ml': 0.0}),
        throwsArgumentError,
      );
      expect(
        () => repo.updateMealEntry(
          'u1',
          'm1',
          {'calculated_protein': double.nan},
        ),
        throwsArgumentError,
      );
    });

    test('updateMealEntry: dokunulmayan alanlar güncellemede etkilenmez', () {
      // Yalnızca not değişiyorsa miktar denetimi tetiklenmemeli —
      // aksi halde "öğünü düzenle" akışı kırılırdı.
      var reachedDb = false;
      when(() => client.from(any())).thenAnswer((_) {
        reachedDb = true;
        throw StateError('beklenen değil');
      });
      expect(
        () => repo.updateMealEntry('u1', 'm1', {'note': 'acı sos'}),
        throwsStateError,
      );
      expect(reachedDb, isTrue,
          reason: 'geçerli kısmi güncelleme DB katmanına ulaşmalı');
    });
  });

  group('2) FoodRepository._customItem — 100g normalizasyonunda bölme güvenliği', () {
    Map<String, dynamic> row({Object? amount, Object? kcal = 250.0}) => {
          'id': 'e1',
          'custom_name': 'Ev yapımı köfte',
          'amount_g_ml': amount,
          'calculated_kcal': kcal,
          'calculated_protein': 20.0,
          'calculated_carbs': 10.0,
          'calculated_fat': 15.0,
        };

    test('miktar 0 → 100g varsayılanı (Infinity istisnası yok)', () {
      final item = FoodRepository.customItem(row(amount: 0));
      expect(item.servingSizeG, 100.0);
      expect(item.calories, 250.0); // 250/100*100
      expect(item.proteinG, 20.0);
    });

    test('miktar null → 100g varsayılanı (web `?? 100` parity)', () {
      final item = FoodRepository.customItem(row(amount: null));
      expect(item.servingSizeG, 100.0);
      expect(item.calories, 250.0);
    });

    test('miktar negatif → 100g varsayılanı, negatif porsiyon üretilmez', () {
      final item = FoodRepository.customItem(row(amount: -50));
      expect(item.servingSizeG, 100.0);
      expect(item.calories.isFinite, isTrue);
      expect(item.calories, greaterThanOrEqualTo(0));
    });

    test('NaN besin değerleri 0 normalizasyonu üretir, istisna atmaz', () {
      final item = FoodRepository.customItem(
        row(amount: 100, kcal: double.nan),
      );
      expect(item.calories, 0.0);
      expect(item.proteinG, 20.0);
    });

    test('normalizasyon 100g başına ölçekler (250g köfte → 100g değeri)', () {
      final item = FoodRepository.customItem(row(amount: 250));
      expect(item.servingSizeG, 250.0);
      expect(item.calories, 100.0); // 250/250*100
      expect(item.proteinG, 8.0); // 20/250*100 = 8
      expect(item.carbsG, 4.0);
      expect(item.fatG, 6.0);
    });
  });

  group('3) MacroCalculator — AI gövdesi alan doğrulaması', () {
    test('NaN içeren AI yanıtı yerel formüle düşer (NaN hedef yazılmaz)', () {
      expect(
        MacroCalculator.goalsFromAiBody(
          <String, dynamic>{
            'bmr': double.nan,
            'tdee': 2400.0,
            'daily_calorie_target': 1900.0,
            'protein_target_g': 140.0,
            'carbs_target_g': 190.0,
            'fat_target_g': 63.0,
          },
          bmi: 24.7,
          weightKg: 80,
        ),
        isNull,
      );
    });

    test('eksik alanlı AI yanıtı yerel formüle düşer', () {
      expect(
        MacroCalculator.goalsFromAiBody(
          <String, dynamic>{
            'bmr': 1800.0,
            'tdee': 2400.0,
            'daily_calorie_target': 1900.0,
            'protein_target_g': 140.0,
            // carbs_target_g yok
            'fat_target_g': 63.0,
          },
          bmi: 24.7,
          weightKg: 80,
        ),
        isNull,
      );
    });

    test('string değerli alan geçersiz sayılır (sessiz `as num` istisnası yok)', () {
      expect(
        MacroCalculator.goalsFromAiBody(
          <String, dynamic>{
            'bmr': '1800',
            'tdee': 2400.0,
            'daily_calorie_target': 1900.0,
            'protein_target_g': 140.0,
            'carbs_target_g': 190.0,
            'fat_target_g': 63.0,
          },
          bmi: 24.7,
          weightKg: 80,
        ),
        isNull,
      );
    });

    test('tam ve sonlu gövde kabul edilir', () {
      final goals = MacroCalculator.goalsFromAiBody(
        <String, dynamic>{
          'bmr': 1800.0,
          'tdee': 2400.0,
          'daily_calorie_target': 1900.0,
          'protein_target_g': 140.0,
          'carbs_target_g': 190.0,
          'fat_target_g': 63.0,
          'daily_water_target_ml': 2640.0,
        },
        bmi: 24.7,
        weightKg: 80,
      );
      expect(goals, isNotNull);
      expect(goals!.bmr, 1800);
      expect(goals.waterTarget, 2640);
      expect(goals.usedAi, isTrue);
    });

    test('su hedefi AI gövdesinde yoksa yerel formül (kg*33) kullanılır', () {
      final goals = MacroCalculator.goalsFromAiBody(
        <String, dynamic>{
          'bmr': 1800.0,
          'tdee': 2400.0,
          'daily_calorie_target': 1900.0,
          'protein_target_g': 140.0,
          'carbs_target_g': 190.0,
          'fat_target_g': 63.0,
        },
        bmi: 24.7,
        weightKg: 80,
      );
      expect(goals!.waterTarget, 2640); // 80 * 33
    });

    test('yerel fallback zinciri sonlu değer üretir (O(N) istisna yok)', () {
      // 0 boy → Calculations.bmi bölme koruması; hedefler yine de üretilir.
      final goals = Calculations.bmr(
        weightKg: 80,
        heightCm: 0,
        age: 30,
        gender: Gender.male,
      );
      expect(goals, greaterThanOrEqualTo(Calculations.minBmr));
      expect(Calculations.bmi(80, 0), 0.0);
    });
  });

  group('4) AnalyticsRepository — takvim günü aritmetiği (DST güvenli)', () {
    setUpAll(() async {
      await initializeDateFormatting('en');
    });

    test('buildDays: 31 günlük aralık tam 31 gün üretir', () {
      final days = AnalyticsRepository.buildDays(
        start: DateTime(2026, 3, 1),
        end: DateTime(2026, 3, 31),
        today: DateTime(2026, 4, 10),
        period: AnalyticsPeriod.month,
        locale: 'en',
      );
      expect(days.length, 31);
      expect(days.first.date, '2026-03-01');
      expect(days.last.date, '2026-03-31');
    });

    test('buildDays: 28 Şubat → 29 (leap) gün sayımı doğru', () {
      final days = AnalyticsRepository.buildDays(
        start: DateTime(2024, 2, 1),
        end: DateTime(2024, 2, 29),
        today: DateTime(2024, 3, 5),
        period: AnalyticsPeriod.month,
        locale: 'en',
      );
      expect(days.length, 29);
      expect(days.last.date, '2024-02-29');
    });

    test('buildDays: ay sonu sınırını aşmaz (31 → sonraki ay değil)', () {
      final days = AnalyticsRepository.buildDays(
        start: DateTime(2026, 1, 30),
        end: DateTime(2026, 2, 2),
        today: DateTime(2026, 2, 10),
        period: AnalyticsPeriod.month,
        locale: 'en',
      );
      expect(days.map((d) => d.date),
          ['2026-01-30', '2026-01-31', '2026-02-01', '2026-02-02']);
    });

    test('buildDays: end > today ise bugüne kırpılır', () {
      final days = AnalyticsRepository.buildDays(
        start: DateTime(2026, 8, 15),
        end: DateTime(2026, 8, 31),
        today: DateTime(2026, 8, 20, 9, 0),
        period: AnalyticsPeriod.month,
        locale: 'en',
      );
      expect(days.length, 6); // 15..20
      expect(days.last.date, '2026-08-20');
    });

    test('dateRange(week): pazartesi–pazar, hafta sonu doğru', () {
      final r = AnalyticsRepository.dateRange(
        AnalyticsPeriod.week,
        DateTime(2026, 8, 15, 14, 30), // Cumartesi
      );
      expect(r.start, DateTime(2026, 8, 10));
      expect(r.end, DateTime(2026, 8, 16));
    });

    test('dateRange(month): Şubat sonu 29 (2024) hesaplanır', () {
      final r = AnalyticsRepository.dateRange(
        AnalyticsPeriod.month,
        DateTime(2024, 2, 10),
      );
      expect(r.start, DateTime(2024, 2, 1));
      expect(r.end, DateTime(2024, 2, 29));
    });

    test('aggregateDaily: bozuk/null satır tüm seriyi düşürmez', () {
      final days = [
        (date: '2026-08-15', dayLabel: '15 Aug'),
        (date: '2026-08-16', dayLabel: '16 Aug'),
      ];
      final stats = AnalyticsRepository.aggregateDaily(
        days: days,
        mealRows: [
          {'entry_date': '2026-08-15', 'calculated_kcal': 300},
          // Bozuk satırlar: null tarih, null sayı, string sayı, NaN sayı.
          {'entry_date': null, 'calculated_kcal': 9999},
          {'entry_date': '2026-08-15', 'calculated_kcal': null},
          {'entry_date': '2026-08-15', 'calculated_kcal': 'yok'},
          {'entry_date': '2026-08-15', 'calculated_kcal': double.nan},
        ],
        waterRows: [
          {'entry_date': '2026-08-16', 'amount_ml': 500},
          {'entry_date': null, 'amount_ml': 1000},
        ],
      );
      expect(stats.length, 2);
      expect(stats[0].calories, 300); // NaN/null/string 0 sayılır
      expect(stats[0].protein, 0.0);
      expect(stats[1].water, 500.0);
      expect(stats[1].calories, 0);
    });

    test('buildWeightTrend: bozuk satırlar seriyi düşürmez', () {
      final points = AnalyticsRepository.buildWeightTrend(
        [
          {'entry_date': '2026-08-15', 'weight_kg': 80.4},
          // Parse edilemeyen tarih → ham dize etiket olarak korunur
          // (tüm trendi düşürmek yerine).
          {'entry_date': 'bozuk-tarih', 'weight_kg': 79.0},
          // Kilosu olmayan satır → seriye giremez.
          {'entry_date': '2026-08-16', 'weight_kg': null},
        ],
        locale: 'en',
      );
      expect(points.length, 2);
      expect(points[0].date, '2026-08-15');
      expect(points[0].dateLabel, '15 Aug');
      expect(points[0].weight, 80.4);
      expect(points[1].dateLabel, 'bozuk-tarih');
      expect(points[1].weight, 79.0);
    });

    test('computeAverages: veri olmayan günler ortalama bölenine girmez', () {
      final stats = AnalyticsRepository.aggregateDaily(
        days: [
          (date: '2026-08-15', dayLabel: 'a'),
          (date: '2026-08-16', dayLabel: 'b'),
          (date: '2026-08-17', dayLabel: 'c'),
        ],
        mealRows: [
          {'entry_date': '2026-08-15', 'calculated_kcal': 3000},
          {'entry_date': '2026-08-16', 'calculated_kcal': 2000},
        ],
        waterRows: [
          {'entry_date': '2026-08-15', 'amount_ml': 1000},
        ],
      );
      final avg = AnalyticsRepository.computeAverages(stats);
      expect(avg.avgCalories, 2500); // (3000+2000)/2, boş gün sayılmaz
      expect(avg.avgWater, 1000); // yalnızca 1 su günü
      expect(avg.totalDays, 3);
      expect(avg.daysWithData, 2);
    });

    test('computeAverages: hiç veri yokken NaN/istisna üretmez', () {
      final stats = AnalyticsRepository.aggregateDaily(
        days: [(date: '2026-08-15', dayLabel: 'a')],
        mealRows: const [],
        waterRows: const [],
      );
      final avg = AnalyticsRepository.computeAverages(stats);
      expect(avg.avgCalories, 0);
      expect(avg.avgWater, 0);
      expect(avg.daysWithData, 0);
    });
  });
}
