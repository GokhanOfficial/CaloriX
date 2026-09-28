/// Analitik sayfasının **grafik kartları** — `analytics_page.dart`'den
/// bölünerek çıkarıldı (A4r6, Tur 6; dosya 1239 satırdı).
///
/// ## Neden bölündü
///
/// `AnalyticsPage` hem ekran iskeletini (periyot sekmeleri, `RefreshIndicator`,
/// odak kaydırma) hem de beş ayrı `fl_chart` grafiğini içeriyordu. Grafikler
/// aynı üç deseni tekrarlıyor (nokta listesi → `maxY` → `LineChart`/`BarChart`
/// → %100 referans çizgisi) ve sayfayı okumak için 1200 satır kaydırmak
/// gerekiyordu. Davranış **hiç** değişmedi: her kart birebir taşındı.
///
/// ## Ortak altyapı
///
/// `analytics_targets.dart`:
///  * `AnalyticsTargets` — profil hedefleri (kcal/P/C/Y/su),
///  * `analyticsPercent` — sıfıra bölme koruması.
///
/// `dailyStats`/`averages`/`weightTrend` veri tipleri
/// `data/repositories/analytics_repository.dart`'dan gelir.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/analytics_repository.dart';
import 'analytics_targets.dart';
import 'macro_focus.dart';

// ===========================================================================
// Per-macro odak grafiği — dashboard makro kartından derin bağlantı
// (`/analytics?macro=protein|carbs|fat`). `CaloriesChartCard` alan grafiği
// deseniyle aynı; tek fark: veri seçici (protein|carbs|fat), renk ve gram
// tooltip. Hedef %100 dashed çizgisi korunur. Backend değişikliği yok —
// `dailyStats` zaten P/C/F içeriyor.
// ===========================================================================
class FocusedMacroChartCard extends StatelessWidget {
  const FocusedMacroChartCard({
    super.key,
    required this.data,
    required this.targets,
    required this.period,
    required this.focus,
  });

  final AnalyticsData data;
  final AnalyticsTargets targets;
  final AnalyticsPeriod period;
  final MacroFocus focus;

  /// Odak makro için ham gram değeri ve hedef gram.
  ({double value, double target}) _pick(DailyStats s) => switch (focus) {
        MacroFocus.protein =>
          (value: s.protein, target: targets.protein),
        MacroFocus.carbs => (value: s.carbs, target: targets.carbs),
        MacroFocus.fat => (value: s.fat, target: targets.fat),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = data.dailyStats;
    final color = focus.color;

    final spots = <FlSpot>[
      for (var i = 0; i < stats.length; i++)
        FlSpot(
          i.toDouble(),
          MacroFocus.percentOfTarget(
            value: _pick(stats[i]).value,
            target: _pick(stats[i]).target,
          ),
        ),
    ];
    final maxY = spots.isEmpty
        ? 150.0
        : [150.0, ...spots.map((s) => s.y + 20)].reduce((a, b) => a > b ? a : b);

    final title = 'analytics.charts.macroFocus.title'
        .tr(namedArgs: {'macro': focus.labelKey.tr()});

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= stats.length) {
                            return const SizedBox.shrink();
                          }
                          // week: her gün; diğer: seyrek (web preserveStartEnd)
                          if (period != AnalyticsPeriod.week &&
                              stats.length > 8 &&
                              i % (stats.length ~/ 5).clamp(1, 99) != 0 &&
                              i != stats.length - 1) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              stats[i].dayLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 100,
                        color: AppColors.success,
                        strokeWidth: 2,
                        dashArray: [5, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: AppColors.success,
                          ),
                          labelResolver: (_) => '100%',
                        ),
                      ),
                    ],
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touched) => [
                        for (final t in touched)
                          if (t.x.toInt() >= 0 && t.x.toInt() < stats.length)
                            LineTooltipItem(
                              '%${t.y.round()} '
                              '(${_pick(stats[t.x.toInt()]).value.toStringAsFixed(1)}g)',
                              theme.textTheme.bodySmall!
                                  .copyWith(color: theme.colorScheme.onSurface),
                            ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.3),
                            color.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Kalori grafiği — hedef %100 referans çizgili alan grafiği
// ===========================================================================
class CaloriesChartCard extends StatelessWidget {
  const CaloriesChartCard({
    super.key,
    required this.data,
    required this.targets,
    required this.period,
  });

  final AnalyticsData data;
  final AnalyticsTargets targets;
  final AnalyticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = data.dailyStats;
    final spots = <FlSpot>[
      for (var i = 0; i < stats.length; i++)
        FlSpot(
          i.toDouble(),
          (stats[i].calories / (targets.calories > 0 ? targets.calories : 1) * 100)
              .roundToDouble(),
        ),
    ];
    final maxY = spots.isEmpty
        ? 150.0
        : [150.0, ...spots.map((s) => s.y + 20)].reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('analytics.charts.calories.title'.tr(),
                    style: theme.textTheme.titleSmall),
                Text(
                  '${'analytics.charts.target'.tr()}: ${targets.calories.round()} kcal',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= stats.length) {
                            return const SizedBox.shrink();
                          }
                          // week: her gün; diğer: seyrek (web preserveStartEnd)
                          if (period != AnalyticsPeriod.week &&
                              stats.length > 8 &&
                              i % (stats.length ~/ 5).clamp(1, 99) != 0 &&
                              i != stats.length - 1) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              stats[i].dayLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 100,
                        color: AppColors.success,
                        strokeWidth: 2,
                        dashArray: [5, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: AppColors.success,
                          ),
                          labelResolver: (_) => '100%',
                        ),
                      ),
                    ],
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touched) => [
                        for (final t in touched)
                          if (t.x.toInt() >= 0 && t.x.toInt() < stats.length)
                            LineTooltipItem(
                              '%${t.y.round()} (${stats[t.x.toInt()].calories} kcal)',
                              theme.textTheme.bodySmall!
                                  .copyWith(color: theme.colorScheme.onSurface),
                            ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: theme.colorScheme.primary,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            theme.colorScheme.primary.withValues(alpha: 0.3),
                            theme.colorScheme.primary.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Makro çubuk grafiği — hedefe göre % (P/K/Y)
// ===========================================================================
class MacrosChartCard extends StatelessWidget {
  const MacrosChartCard({
    super.key,
    required this.data,
    required this.targets,
    required this.period,
  });

  final AnalyticsData data;
  final AnalyticsTargets targets;
  final AnalyticsPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = data.dailyStats;

    // Hedef 0/negatifse grafik yüzdeleri 0 (sıfıra bölme koruması).
    final pTarget = targets.protein > 0 ? targets.protein : 1.0;
    final cTarget = targets.carbs > 0 ? targets.carbs : 1.0;
    final fTarget = targets.fat > 0 ? targets.fat : 1.0;

    final groups = <BarChartGroupData>[
      for (var i = 0; i < stats.length; i++)
        BarChartGroupData(
          x: i,
          barsSpace: 2,
          barRods: [
            _rod((stats[i].protein / pTarget * 100).roundToDouble(),
                AppColors.macroProtein),
            _rod((stats[i].carbs / cTarget * 100).roundToDouble(),
                AppColors.macroCarbs),
            _rod((stats[i].fat / fTarget * 100).roundToDouble(),
                AppColors.macroFat),
          ],
        ),
    ];
    final maxY = stats.isEmpty
        ? 150.0
        : <double>[
            150.0,
            ...stats.expand((s) => [
                  (s.protein / pTarget * 100).roundToDouble(),
                  (s.carbs / cTarget * 100).roundToDouble(),
                  (s.fat / fTarget * 100).roundToDouble(),
                  20.0,
                ])
          ].reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('analytics.charts.macros.title'.tr(),
                      style: theme.textTheme.titleSmall),
                ),
                Text(
                  'analytics.charts.macros.subtitle'.tr(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxY,
                  barGroups: groups,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= stats.length) {
                            return const SizedBox.shrink();
                          }
                          if (period != AnalyticsPeriod.week &&
                              stats.length > 8 &&
                              i % (stats.length ~/ 5).clamp(1, 99) != 0 &&
                              i != stats.length - 1) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              stats[i].dayLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 100,
                        color: AppColors.success,
                        strokeWidth: 2,
                        dashArray: [5, 5],
                      ),
                    ],
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, gi, rod, ri) {
                        // Makro adları `analytics.macros.*` çeviri
                        // anahtarlarından; sabit Türkçe liste EN kullanıcısında
                        // tooltip'i Türkçe bırakıyordu.
                        final names = MacroFocus.values[ri].labelKey.tr();
                        return BarTooltipItem(
                          '%${rod.toY.round()}',
                          theme.textTheme.bodySmall!.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                          children: [
                            TextSpan(
                              text: ' ${names[ri]}',
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(theme, AppColors.macroProtein,
                    'P: ${targets.protein.round()}g'),
                const SizedBox(width: 16),
                _legendDot(theme, AppColors.macroCarbs,
                    'K: ${targets.carbs.round()}g'),
                const SizedBox(width: 16),
                _legendDot(theme, AppColors.macroFat,
                    'Y: ${targets.fat.round()}g'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  BarChartRodData _rod(double y, Color color) => BarChartRodData(
        toY: y,
        color: color,
        width: 6,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      );

  Widget _legendDot(ThemeData theme, Color color, String text) => Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
}

// ===========================================================================
// Makro ortalamaları — ilerleme çubukları
// ===========================================================================
class MacroAveragesCard extends StatelessWidget {
  const MacroAveragesCard({
    super.key,
    required this.data,
    required this.targets,
  });

  final AnalyticsData data;
  final AnalyticsTargets targets;

  @override
  Widget build(BuildContext context) {
    final avg = data.averages;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('analytics.averages.title'.tr(),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 16),
            _avgRow(context, 'settings.goals.protein'.tr(), avg.avgProtein,
                targets.protein, AppColors.macroProtein),
            const SizedBox(height: 12),
            _avgRow(context, 'settings.goals.carbs'.tr(), avg.avgCarbs,
                targets.carbs, AppColors.macroCarbs),
            const SizedBox(height: 12),
            _avgRow(context, 'settings.goals.fat'.tr(), avg.avgFat,
                targets.fat, AppColors.macroFat),
          ],
        ),
      ),
    );
  }

  Widget _avgRow(BuildContext context, String label, double value,
      double target, Color color) {
    final theme = Theme.of(context);
    final percent = target > 0 ? (value / target * 100) : 0.0;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(
              '${_fmt(value)}g / ${target.round()}g',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: (percent / 100).clamp(0.0, 1.0),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
          color: color,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

// ===========================================================================
// Kilo trendi — çizgi grafik + ilk/değişim/son
// ===========================================================================
class WeightTrendCard extends StatelessWidget {
  const WeightTrendCard({required this.data, super.key});

  final AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trend = data.weightTrend;
    final first = trend.first.weight;
    final last = trend.last.weight;
    final change = last - first;

    final minW = trend.map((e) => e.weight).reduce((a, b) => a < b ? a : b);
    final maxW = trend.map((e) => e.weight).reduce((a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('analytics.stats.weightChange'.tr(),
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  minY: minW - 1,
                  maxY: maxW + 1,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: const AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= trend.length) {
                            return const SizedBox.shrink();
                          }
                          // preserveStartEnd: ilk, orta, son
                          if (trend.length > 6 &&
                              i != 0 &&
                              i != trend.length - 1 &&
                              i != trend.length ~/ 2) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              trend[i].dateLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touched) => [
                        for (final t in touched)
                          LineTooltipItem(
                            '${t.y.toStringAsFixed(1)} kg',
                            theme.textTheme.bodySmall!
                                .copyWith(color: theme.colorScheme.onSurface),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < trend.length; i++)
                          FlSpot(i.toDouble(), trend[i].weight),
                      ],
                      isCurved: true,
                      color: AppColors.success,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 3,
                          color: AppColors.success,
                          strokeWidth: 0,
                          strokeColor: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _weightStat(context, 'analytics.weightTrend.first'.tr(),
                    '${first.toStringAsFixed(1)} kg', null),
                _weightStat(
                  context,
                  'analytics.weightTrend.change'.tr(),
                  '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg',
                  change <= 0 ? AppColors.success : AppColors.warning,
                ),
                _weightStat(context, 'analytics.weightTrend.last'.tr(),
                    '${last.toStringAsFixed(1)} kg', null,
                    alignEnd: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _weightStat(BuildContext context, String label, String value,
      Color? valueColor,
      {bool alignEnd = false}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Veri özeti
// ===========================================================================
class SummaryCard extends StatelessWidget {
  const SummaryCard({required this.data, super.key});

  final AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avg = data.averages;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('analytics.summary.daysWithData'.tr(),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            Text(
              '${avg.daysWithData} / ${avg.totalDays} ${'analytics.summary.day'.tr()}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
