import 'package:calorix/data/repositories/analytics_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// AnalyticsRepository'nin saf (Supabase'siz) hesapları.
/// Web parity referansı: `src/hooks/useAnalyticsData.ts`.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });
  group('dateRange', () {
    // 2026-08-15 bir Cumartesi (weekday: 6).
    final today = DateTime(2026, 8, 15, 14, 30);

    test('week → Pazartesi–Pazar (weekStartsOn: 1 parity)', () {
      final r = AnalyticsRepository.dateRange(AnalyticsPeriod.week, today);
      expect(r.start, DateTime(2026, 8, 10)); // Pazartesi
      expect(r.end, DateTime(2026, 8, 16)); // Pazar
    });

    test('month → takvim ayı (1 … son gün)', () {
      final r = AnalyticsRepository.dateRange(AnalyticsPeriod.month, today);
      expect(r.start, DateTime(2026, 8, 1));
      expect(r.end, DateTime(2026, 8, 31));
    });

    test('month → Şubat 28 gün', () {
      final r = AnalyticsRepository.dateRange(
          AnalyticsPeriod.month, DateTime(2026, 2, 10));
      expect(r.start, DateTime(2026, 2, 1));
      expect(r.end, DateTime(2026, 2, 28));
    });

    test('3months → bugün − 90 gün … bugün (subDays parity)', () {
      final r =
          AnalyticsRepository.dateRange(AnalyticsPeriod.threeMonths, today);
      expect(r.end, DateTime(2026, 8, 15));
      // date-only today − 90 gün
      expect(r.start,
          DateTime(2026, 8, 15).subtract(const Duration(days: 90)));
      expect(r.start, DateTime(2026, 5, 17));
    });

    test('saat bileşeni sıfırlanır (date-only)', () {
      final r = AnalyticsRepository.dateRange(AnalyticsPeriod.week, today);
      expect(r.start.hour, 0);
      expect(r.start.minute, 0);
    });
  });

  group('buildDays', () {
    final today = DateTime(2026, 8, 15); // Cumartesi

    test('week: Pazartesi–bugün arası (end bugüne kırpılır)', () {
      final days = AnalyticsRepository.buildDays(
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 16), // Pazar — kırpılacak
        today: today,
        period: AnalyticsPeriod.week,
        locale: 'en',
      );
      expect(days.map((d) => d.date), [
        '2026-08-10',
        '2026-08-11',
        '2026-08-12',
        '2026-08-13',
        '2026-08-14',
        '2026-08-15',
      ]);
      // week etiketi EEE
      expect(days.first.dayLabel, 'Mon');
      expect(days.last.dayLabel, 'Sat');
    });

    test('month: etiket "d MMM" formatı', () {
      final days = AnalyticsRepository.buildDays(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 31),
        today: today,
        period: AnalyticsPeriod.month,
        locale: 'en',
      );
      expect(days.length, 15);
      expect(days.first.dayLabel, '1 Aug');
      expect(days.last.dayLabel, '15 Aug');
    });

    test('start > today ise boş liste', () {
      final days = AnalyticsRepository.buildDays(
        start: DateTime(2026, 8, 20),
        end: DateTime(2026, 8, 26),
        today: today,
        period: AnalyticsPeriod.week,
        locale: 'en',
      );
      expect(days, isEmpty);
    });
  });

  group('aggregateDaily', () {
    final days = [
      (date: '2026-08-10', dayLabel: 'Mon'),
      (date: '2026-08-11', dayLabel: 'Tue'),
      (date: '2026-08-12', dayLabel: 'Wed'),
    ];

    test('kalori round, makrolar 1 ondalık, su ham (web parity)', () {
      final stats = AnalyticsRepository.aggregateDaily(
        days: days,
        mealRows: [
          {
            'entry_date': '2026-08-10',
            'calculated_kcal': 500.4,
            'calculated_protein': 30.04,
            'calculated_carbs': 50.05,
            'calculated_fat': 20.06,
          },
          {
            'entry_date': '2026-08-10',
            'calculated_kcal': 250.2,
            'calculated_protein': 10.01,
            'calculated_carbs': 25.05,
            'calculated_fat': 5.04,
          },
        ],
        waterRows: [
          {'entry_date': '2026-08-10', 'amount_ml': 250},
          {'entry_date': '2026-08-10', 'amount_ml': 500},
          {'entry_date': '2026-08-11', 'amount_ml': 250},
        ],
      );

      // 2026-08-10: 750.6 → 750; protein 40.05 → 40.1? No: round(40.05*10)/10 = round(400.5)/10 = 401/10 = 40.1
      // dikkat: Dart (x*10).round() banker's yuvarlama yapmaz, uzaklaştırır: 400.5 → 401
      expect(stats[0].calories, 751); // 750.6 → 751
      expect(stats[0].protein, 40.1);
      expect(stats[0].carbs, 75.1);
      expect(stats[0].fat, 25.1);
      expect(stats[0].water, 750);
      expect(stats[0].hasData, isTrue);

      // Sadece su olan gün
      expect(stats[1].calories, 0);
      expect(stats[1].water, 250);
      expect(stats[1].hasData, isTrue);

      // Verisiz gün
      expect(stats[2].hasData, isFalse);
      expect(stats[2].calories, 0);
    });

    test('boş satırlarda hasData=false, sıfırlar', () {
      final stats = AnalyticsRepository.aggregateDaily(
        days: days,
        mealRows: const [],
        waterRows: const [],
      );
      expect(stats.every((s) => !s.hasData), isTrue);
      expect(stats.every((s) => s.calories == 0 && s.water == 0), isTrue);
    });
  });

  group('computeAverages', () {
    DailyStats day({
      required int calories,
      double protein = 0,
      double carbs = 0,
      double fat = 0,
      double water = 0,
      bool hasData = false,
    }) =>
        DailyStats(
          date: '2026-08-10',
          dayLabel: 'Mon',
          calories: calories,
          protein: protein,
          carbs: carbs,
          fat: fat,
          water: water,
          hasData: hasData,
        );

    test('ortalamalar yalnızca o veri tipi olan günlere bölünür', () {
      final stats = [
        day(calories: 2000, protein: 150, carbs: 200, fat: 65, water: 2000,
            hasData: true),
        day(calories: 1000, protein: 50, carbs: 100, fat: 35,
            hasData: true), // su yok
        day(calories: 0, hasData: false), // boş gün — ortalamaya girmez
      ];
      final avg = AnalyticsRepository.computeAverages(stats);

      expect(avg.avgCalories, 1500); // (2000+1000)/2
      expect(avg.avgProtein, 100); // (150+50)/2
      expect(avg.avgWater, 2000); // yalnızca 1 gün su var → /1
      expect(avg.totalDays, 3);
      expect(avg.daysWithData, 2);
    });

    test('hiç veri yoksa bölme sıfıra düşmez (|| 1 parity)', () {
      final avg = AnalyticsRepository.computeAverages(const []);
      expect(avg.avgCalories, 0);
      expect(avg.avgWater, 0);
      expect(avg.totalDays, 0);
      expect(avg.daysWithData, 0);
    });

    test('makro ortalamaları 1 ondalığa yuvarlanır', () {
      final stats = [
        day(calories: 100, protein: 33.33, carbs: 10.05, fat: 5.55,
            hasData: true),
        day(calories: 100, protein: 10.11, carbs: 20.02, fat: 1.11,
            hasData: true),
      ];
      final avg = AnalyticsRepository.computeAverages(stats);
      expect(avg.avgProtein, 21.7); // 43.44/2 = 21.72 → 21.7
      expect(avg.avgCarbs, 15.0); // 30.07/2 = 15.035 → 15.0
      expect(avg.avgFat, 3.3); // 6.66/2 = 3.33 → 3.3
    });
  });

  group('buildWeightTrend', () {
    test('tüm satırlar sırayla, etiket "d MMM"', () {
      final trend = AnalyticsRepository.buildWeightTrend([
        {'entry_date': '2026-08-01', 'weight_kg': 82.5},
        {'entry_date': '2026-08-15', 'weight_kg': 81.0},
      ], locale: 'en');
      expect(trend.length, 2);
      expect(trend[0].weight, 82.5);
      expect(trend[0].dateLabel, '1 Aug');
      expect(trend[1].dateLabel, '15 Aug');
    });

    test('boş listede boş trend', () {
      expect(AnalyticsRepository.buildWeightTrend(const []), isEmpty);
    });
  });
}
