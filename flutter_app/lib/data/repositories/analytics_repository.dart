import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';
import 'diary_repository.dart';

/// Analitik periyodu — web `useAnalyticsData`'daki `Period` ile aynı.
enum AnalyticsPeriod { week, month, threeMonths }

/// Tek günün agregasyonu (web `DailyStats` karşılığı).
class DailyStats {
  const DailyStats({
    required this.date,
    required this.dayLabel,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.water,
    required this.hasData,
  });

  /// `yyyy-MM-dd`
  final String date;
  final String dayLabel;
  final int calories;
  final double protein;
  final double carbs;
  final double fat;
  final double water;
  final bool hasData;
}

/// Kilo trendi noktası (web `WeightTrend` karşılığı).
class WeightPoint {
  const WeightPoint({
    required this.date,
    required this.dateLabel,
    required this.weight,
  });

  final String date;
  final String dateLabel;
  final double weight;
}

/// Ortalama istatistikler (web `AverageStats` karşılığı).
class AverageStats {
  const AverageStats({
    required this.avgCalories,
    required this.avgProtein,
    required this.avgCarbs,
    required this.avgFat,
    required this.avgWater,
    required this.totalDays,
    required this.daysWithData,
  });

  final int avgCalories;
  final double avgProtein;
  final double avgCarbs;
  final double avgFat;
  final int avgWater;
  final int totalDays;
  final int daysWithData;

  static const empty = AverageStats(
    avgCalories: 0,
    avgProtein: 0,
    avgCarbs: 0,
    avgFat: 0,
    avgWater: 0,
    totalDays: 0,
    daysWithData: 0,
  );
}

/// Tek sorgu sonucu — günlük seriler + kilo trendi + ortalamalar.
class AnalyticsData {
  const AnalyticsData({
    required this.dailyStats,
    required this.weightTrend,
    required this.averages,
  });

  final List<DailyStats> dailyStats;
  final List<WeightPoint> weightTrend;
  final AverageStats averages;

  static const empty = AnalyticsData(
    dailyStats: [],
    weightTrend: [],
    averages: AverageStats.empty,
  );
}

/// Web `useAnalyticsData` hook'unun Dart karşılığı.
///
/// Sorgular Supabase'e gider (`fetch`); tarih aralığı, gün üretimi,
/// agregasyon ve ortalama hesapları **saf statik fonksiyonlardır**
/// (unit testlerde Supabase'siz doğrulanır).
class AnalyticsRepository {
  AnalyticsRepository(this._client);

  final SupabaseClient _client;

  // ------------------------------------------------------------------
  // Saf hesaplar (web parity — test edilebilir)
  // ------------------------------------------------------------------

  /// Web `getDateRange` parity:
  /// - week   → Pazartesi–Pazar (`startOfWeek`/`endOfWeek`, weekStartsOn: 1)
  /// - month  → takvim ayı
  /// - 3months→ bugün − 90 gün … bugün
  ///
  /// `today` parametre olarak verilir ki testler deterministik olsun
  /// (web'de `new Date()`).
  static ({DateTime start, DateTime end}) dateRange(
    AnalyticsPeriod period,
    DateTime today,
  ) {
    final day = DateTime(today.year, today.month, today.day);
    switch (period) {
      case AnalyticsPeriod.week:
        // DateTime.weekday: Pazartesi=1 … Pazar=7
        final start = day.subtract(Duration(days: day.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return (start: start, end: end);
      case AnalyticsPeriod.month:
        final start = DateTime(day.year, day.month);
        final end = DateTime(day.year, day.month + 1, 0);
        return (start: start, end: end);
      case AnalyticsPeriod.threeMonths:
        return (start: day.subtract(const Duration(days: 90)), end: day);
    }
  }

  /// Web `eachDayOfInterval({start, end: min(end, today)})` parity —
  /// gün listesi bugüne kırpılır. [dayLabel]: week → `EEE`, diğer → `d MMM`.
  static List<({String date, String dayLabel})> buildDays({
    required DateTime start,
    required DateTime end,
    required DateTime today,
    required AnalyticsPeriod period,
    String? locale,
  }) {
    final effectiveEnd = end.isAfter(today) ? today : end;
    final pattern = period == AnalyticsPeriod.week ? 'EEE' : 'd MMM';
    final labelFmt = DateFormat(pattern, locale);
    final days = <({String date, String dayLabel})>[];
    for (var d = DateTime(start.year, start.month, start.day);
        !d.isAfter(effectiveEnd);
        d = d.add(const Duration(days: 1))) {
      days.add((date: formatEntryDate(d), dayLabel: labelFmt.format(d)));
    }
    return days;
  }

  /// Ham satırlardan günlük seri (web `stats` map'i parity):
  /// kalori `round`, makrolar 1 ondalık, su ham toplam.
  static List<DailyStats> aggregateDaily({
    required List<({String date, String dayLabel})> days,
    required List<Map<String, dynamic>> mealRows,
    required List<Map<String, dynamic>> waterRows,
  }) {
    final mealsByDate = <String, List<double>>{}; // [kcal, p, c, f]
    for (final m in mealRows) {
      final date = m['entry_date'] as String;
      final acc = mealsByDate.putIfAbsent(date, () => [0, 0, 0, 0]);
      acc[0] += (m['calculated_kcal'] as num).toDouble();
      acc[1] += (m['calculated_protein'] as num).toDouble();
      acc[2] += (m['calculated_carbs'] as num).toDouble();
      acc[3] += (m['calculated_fat'] as num).toDouble();
    }
    final waterByDate = <String, double>{};
    for (final w in waterRows) {
      final date = w['entry_date'] as String;
      waterByDate[date] =
          (waterByDate[date] ?? 0) + (w['amount_ml'] as num).toDouble();
    }

    double round1(num v) => (v * 10).roundToDouble() / 10;

    return [
      for (final day in days)
        DailyStats(
          date: day.date,
          dayLabel: day.dayLabel,
          calories: (mealsByDate[day.date]?[0] ?? 0).round(),
          protein: round1(mealsByDate[day.date]?[1] ?? 0),
          carbs: round1(mealsByDate[day.date]?[2] ?? 0),
          fat: round1(mealsByDate[day.date]?[3] ?? 0),
          water: waterByDate[day.date] ?? 0,
          hasData: mealsByDate.containsKey(day.date) ||
              waterByDate.containsKey(day.date),
        ),
    ];
  }

  /// Web `setAverages` parity — ortalamalar yalnızca o veri tipi olan
  /// günlere bölünür; bölen en az 1.
  static AverageStats computeAverages(List<DailyStats> stats) {
    final daysWithMeals = stats.where((s) => s.calories > 0).toList();
    final daysWithWater = stats.where((s) => s.water > 0).toList();
    final mealCount = daysWithMeals.isEmpty ? 1 : daysWithMeals.length;
    final waterCount = daysWithWater.isEmpty ? 1 : daysWithWater.length;

    double sumOf(List<DailyStats> list, num Function(DailyStats) pick) =>
        list.fold<double>(0, (sum, s) => sum + pick(s).toDouble());
    double round1(num v) => (v * 10).roundToDouble() / 10;

    return AverageStats(
      avgCalories: (sumOf(daysWithMeals, (s) => s.calories) / mealCount)
          .round(),
      avgProtein: round1(sumOf(daysWithMeals, (s) => s.protein) / mealCount),
      avgCarbs: round1(sumOf(daysWithMeals, (s) => s.carbs) / mealCount),
      avgFat: round1(sumOf(daysWithMeals, (s) => s.fat) / mealCount),
      avgWater: (sumOf(daysWithWater, (s) => s.water) / waterCount).round(),
      totalDays: stats.length,
      daysWithData: stats.where((s) => s.hasData).length,
    );
  }

  /// Web `weightData` parity — tüm zamanlar, tarih sıralı; etiket `d MMM`.
  static List<WeightPoint> buildWeightTrend(
    List<Map<String, dynamic>> weightRows, {
    String? locale,
  }) {
    final fmt = DateFormat('d MMM', locale);
    return [
      for (final w in weightRows)
        WeightPoint(
          date: w['entry_date'] as String,
          dateLabel:
              fmt.format(DateTime.parse(w['entry_date'] as String)),
          weight: (w['weight_kg'] as num).toDouble(),
        ),
    ];
  }

  // ------------------------------------------------------------------
  // Supabase sorgusu (web `fetchData` parity — 3 paralel sorgu)
  // ------------------------------------------------------------------

  Future<AnalyticsData> fetch(
    String userId,
    AnalyticsPeriod period, {
    String? locale,
  }) async {
    final today = DateTime.now();
    final range = dateRange(period, today);
    final startStr = formatEntryDate(range.start);
    final endStr = formatEntryDate(range.end);

    final mealsFuture = _client
        .from('meal_entries')
        .select(
          'entry_date, calculated_kcal, calculated_protein, calculated_carbs, calculated_fat',
        )
        .eq('user_id', userId)
        .gte('entry_date', startStr)
        .lte('entry_date', endStr)
        .isFilter('deleted_at', null);

    final waterFuture = _client
        .from('water_entries')
        .select('entry_date, amount_ml')
        .eq('user_id', userId)
        .gte('entry_date', startStr)
        .lte('entry_date', endStr)
        .isFilter('deleted_at', null);

    // Kilo trendi tüm zamanları kapsar (web parity — tarih filtresi yok).
    final weightsFuture = _client
        .from('weight_entries')
        .select('entry_date, weight_kg')
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('entry_date', ascending: true);

    final results = await Future.wait([
      mealsFuture,
      waterFuture,
      weightsFuture,
    ]);
    final mealRows = results[0].cast<Map<String, dynamic>>();
    final waterRows = results[1].cast<Map<String, dynamic>>();
    final weightRows = results[2].cast<Map<String, dynamic>>();

    final days = buildDays(
      start: range.start,
      end: range.end,
      today: today,
      period: period,
      locale: locale,
    );
    final stats = aggregateDaily(
      days: days,
      mealRows: mealRows,
      waterRows: waterRows,
    );

    return AnalyticsData(
      dailyStats: stats,
      weightTrend: buildWeightTrend(weightRows, locale: locale),
      averages: computeAverages(stats),
    );
  }
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(ref.watch(supabaseClientProvider));
});

/// Seçili periyot — analitik sayfası sekmeleri.
final analyticsPeriodProvider =
    StateProvider<AnalyticsPeriod>((ref) => AnalyticsPeriod.week);

/// Web `useAnalyticsData(period)` karşılığı.
///
/// `locale` (ör. `context.locale.languageCode`) DateFormat etiketleri
/// (`EEE` / `d MMM`) için family parametresi — dil değişince provider
/// otomatik yeniden sorgular.
final analyticsDataProvider =
    FutureProvider.family<AnalyticsData, String>((ref, locale) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return AnalyticsData.empty;
  final period = ref.watch(analyticsPeriodProvider);
  return ref
      .watch(analyticsRepositoryProvider)
      .fetch(user.id, period, locale: locale);
});
