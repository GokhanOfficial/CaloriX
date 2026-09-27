import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/profile_repository.dart';
import 'macro_focus.dart';

/// Analitik sayfası — web `AnalyticsPage.tsx` karşılığı.
///
/// Periyot sekmeleri (Hafta / Ay / 3 Ay), 4 istatistik kartı,
/// kalori alan grafiği (hedef %100 çizgili), makro çubuk grafiği,
/// makro ortalamaları ilerleme çubukları ve kilo trendi.
///
/// `focusedMacro` (isteğe bağlı) `/analytics?macro=protein|carbs|fat` sorgu
/// parametresinden gelir; seçili makro için kalori grafiğinin üstünde ek
/// bir per-macro takip kartı gösterir ve görünür alanı ona kaydırır.
class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key, this.focusedMacro});

  final MacroFocus? focusedMacro;

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  final _scrollController = ScrollController();
  final _focusChartKey = GlobalKey();
  bool _scrolledToFocus = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Veri yüklendikten sonra per-macro odak kartına bir kez kaydır (vurgu).
  void _maybeScrollToFocus() {
    if (widget.focusedMacro == null || _scrolledToFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final ctx = _focusChartKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      _scrolledToFocus = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.locale.languageCode;
    final dataAsync = ref.watch(analyticsDataProvider(locale));
    final profileAsync = ref.watch(profileProvider);
    final period = ref.watch(analyticsPeriodProvider);

    final profile = profileAsync.valueOrNull;
    final targets = _Targets.fromProfile(profile);
    final focus = widget.focusedMacro;

    return Scaffold(
      appBar: AppBar(title: Text('analytics.title'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SegmentedButton<AnalyticsPeriod>(
              segments: [
                ButtonSegment(
                  value: AnalyticsPeriod.week,
                  label: Text('analytics.period.week'.tr()),
                ),
                ButtonSegment(
                  value: AnalyticsPeriod.month,
                  label: Text('analytics.period.month'.tr()),
                ),
                ButtonSegment(
                  value: AnalyticsPeriod.threeMonths,
                  label: Text('analytics.period.3months'.tr()),
                ),
              ],
              selected: {period},
              onSelectionChanged: (s) =>
                  ref.read(analyticsPeriodProvider.notifier).state = s.first,
            ),
          ),
          Expanded(
            child: dataAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                onRetry: () => ref.invalidate(analyticsDataProvider(locale)),
              ),
              data: (data) {
                if (focus != null) _maybeScrollToFocus();
                return RefreshIndicator(
                  // Yalnızca `invalidate` çağırmak `onRefresh`'in Future'ünü
                  // hemen tamamlıyordu: kullanıcı parmağını çekerken veri
                  // hâlâ yükleniyordu, spinner kaybolup eski veri gösteriliyor
                  // ve "yenilendi" izlenimi yanıltıcı oluyordu. Yeni verinin
                  // gelmesini bekle.
                  onRefresh: () => ref.refresh(analyticsDataProvider(locale).future),
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _StatGrid(data: data, targets: targets),
                      const SizedBox(height: 16),
                      if (focus != null) ...[
                        _FocusedMacroChartCard(
                          key: _focusChartKey,
                          data: data,
                          targets: targets,
                          period: period,
                          focus: focus,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _CaloriesChartCard(
                          data: data, targets: targets, period: period),
                      const SizedBox(height: 16),
                      _MacrosChartCard(
                          data: data, targets: targets, period: period),
                      const SizedBox(height: 16),
                      _MacroAveragesCard(data: data, targets: targets),
                      if (data.weightTrend.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _WeightTrendCard(data: data),
                      ],
                      const SizedBox(height: 16),
                      _SummaryCard(data: data),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Hedefler — profilden, yoksa web `DEFAULT_GOALS` değerleri.
class _Targets {
  const _Targets({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.water,
  });

  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double water;

  factory _Targets.fromProfile(Profile? p) => _Targets(
        calories:
            (p?.dailyCalorieTarget ?? AppConstants.defaultCalories).toDouble(),
        protein: (p?.proteinTargetG ?? AppConstants.defaultProtein).toDouble(),
        carbs: (p?.carbsTargetG ?? AppConstants.defaultCarbs).toDouble(),
        fat: (p?.fatTargetG ?? AppConstants.defaultFat).toDouble(),
        water: (p?.dailyWaterTargetMl ?? AppConstants.defaultWater).toDouble(),
      );
}

// ---------------------------------------------------------------------------
// Hata durumu — retry butonu (dashboard `_ErrorBody` ile aynı davranış).
// ---------------------------------------------------------------------------
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('common.error'.tr(), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text('common.resend'.tr()),
          ),
        ],
      ),
    );
  }
}

/// Hedef yüzdesi — hedef 0/NaN/negatifse 0 (sıfıra bölme koruması).
int _percent(num value, num target) {
  if (target <= 0 || target.isNaN) return 0;
  return (value / target * 100).round();
}

// ---------------------------------------------------------------------------
// 4 istatistik kartı (web renk kuralları parity)
// ---------------------------------------------------------------------------
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.data, required this.targets});

  final AnalyticsData data;
  final _Targets targets;

  @override
  Widget build(BuildContext context) {
    final avg = data.averages;

    // Hedef 0/NaN olabilir (bozuk profil satırı) → bölmeden 0 döndür.
    final calPercent = _percent(avg.avgCalories, targets.calories);
    final waterPercent = _percent(avg.avgWater, targets.water);
    final proteinPercent = _percent(avg.avgProtein, targets.protein);

    final trend = data.weightTrend;
    final first = trend.isNotEmpty ? trend.first.weight : null;
    final last = trend.isNotEmpty ? trend.last.weight : null;
    final change = (first != null && last != null) ? last - first : 0.0;
    final changePercent =
        first != null && first != 0 ? (change / first * 100) : 0.0;

    // Web renk kuralları:
    Color calColor = calPercent >= 90 && calPercent <= 110
        ? AppColors.success
        : calPercent < 90
            ? AppColors.warning
            : AppColors.destructive;
    final waterColor =
        waterPercent >= 80 ? AppColors.success : AppColors.warning;
    final proteinColor =
        proteinPercent >= 90 ? AppColors.success : AppColors.warning;
    final weightColor =
        change <= 0 ? AppColors.success : AppColors.warning;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        _StatCard(
          icon: Icons.local_fire_department,
          iconColor: Theme.of(context).colorScheme.primary,
          label: 'analytics.stats.avgCalories'.tr(),
          value: '${avg.avgCalories}',
          footnote: '%$calPercent',
          footnoteColor: calColor,
          targetSuffix: 'analytics.stats.target'.tr(),
        ),
        _StatCard(
          icon: Icons.water_drop,
          iconColor: AppColors.info,
          label: 'analytics.stats.avgWater'.tr(),
          value: '${avg.avgWater} ml',
          footnote: '%$waterPercent',
          footnoteColor: waterColor,
          targetSuffix: 'analytics.stats.target'.tr(),
        ),
        _StatCard(
          icon: Icons.adjust,
          iconColor: AppColors.macroProtein,
          label: 'analytics.stats.avgProtein'.tr(),
          value: '${avg.avgProtein}g',
          footnote: '%$proteinPercent',
          footnoteColor: proteinColor,
          targetSuffix: 'analytics.stats.target'.tr(),
        ),
        _StatCard(
          icon: Icons.monitor_weight,
          iconColor: AppColors.success,
          label: 'analytics.stats.weightChange'.tr(),
          value:
              '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg',
          footnote: '%${changePercent.toStringAsFixed(1)}',
          footnoteColor: weightColor,
          trendIcon: change < 0
              ? Icons.trending_down
              : change > 0
                  ? Icons.trending_up
                  : null,
          trendIconColor: weightColor,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.footnote,
    required this.footnoteColor,
    this.targetSuffix,
    this.trendIcon,
    this.trendIconColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String footnote;
  final Color footnoteColor;
  final String? targetSuffix;
  final IconData? trendIcon;
  final Color? trendIconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (trendIcon != null) ...[
                  Icon(trendIcon, size: 12, color: trendIconColor),
                  const SizedBox(width: 2),
                ],
                Text(
                  footnote,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: footnoteColor),
                ),
                if (targetSuffix != null)
                  Text(
                    ' $targetSuffix',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-macro odak grafiği — dashboard makro kartından derin bağlantı
// (`/analytics?macro=protein|carbs|fat`). `_CaloriesChartCard` alan grafiği
// deseniyle aynı; tek fark: veri seçici (protein|carbs|fat), renk ve gram
// tooltip. Hedef %100 dashed çizgisi korunur. Backend değişikliği yok —
// `dailyStats` zaten P/C/F içeriyor.
// ---------------------------------------------------------------------------
class _FocusedMacroChartCard extends StatelessWidget {
  const _FocusedMacroChartCard({
    super.key,
    required this.data,
    required this.targets,
    required this.period,
    required this.focus,
  });

  final AnalyticsData data;
  final _Targets targets;
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

// ---------------------------------------------------------------------------
// Kalori grafiği — hedef %100 referans çizgili alan grafiği
// ---------------------------------------------------------------------------
class _CaloriesChartCard extends StatelessWidget {
  const _CaloriesChartCard({
    required this.data,
    required this.targets,
    required this.period,
  });

  final AnalyticsData data;
  final _Targets targets;
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

// ---------------------------------------------------------------------------
// Makro çubuk grafiği — hedefe göre % (P/K/Y)
// ---------------------------------------------------------------------------
class _MacrosChartCard extends StatelessWidget {
  const _MacrosChartCard({
    required this.data,
    required this.targets,
    required this.period,
  });

  final AnalyticsData data;
  final _Targets targets;
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

// ---------------------------------------------------------------------------
// Makro ortalamaları — ilerleme çubukları
// ---------------------------------------------------------------------------
class _MacroAveragesCard extends StatelessWidget {
  const _MacroAveragesCard({required this.data, required this.targets});

  final AnalyticsData data;
  final _Targets targets;

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

// ---------------------------------------------------------------------------
// Kilo trendi — çizgi grafik + ilk/değişim/son
// ---------------------------------------------------------------------------
class _WeightTrendCard extends StatelessWidget {
  const _WeightTrendCard({required this.data});

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

// ---------------------------------------------------------------------------
// Veri özeti
// ---------------------------------------------------------------------------
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

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
