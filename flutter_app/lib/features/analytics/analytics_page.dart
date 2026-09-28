import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/analytics_repository.dart';
import '../../data/repositories/profile_repository.dart';
import 'analytics_charts.dart';
import 'analytics_targets.dart';
import 'analytics_views.dart';
import 'macro_focus.dart';

/// Analitik sayfası — web `AnalyticsPage.tsx` karşılığı.
///
/// Periyot sekmeleri (Hafta / Ay / 3 Ay), 4 istatistik kartı,
/// kalori alan grafiği (hedef %100 çizgili), makro çubuk grafiği,
/// makro ortalamaları ilerleme çubukları ve kilo trendi.
///
/// `focusedMacro` (isteçe bağlı) `/analytics?macro=protein|carbs|fat` sorgu
/// parametresinden gelir; seçili makro için kalori grafiğinin üstünde ek
/// bir per-macro takip kartı gösterir ve görünür alanı ona kaydırır.
///
/// ## Dosya bölümü (A4r6, Tur 6)
///
/// Bu dosya artık yalnız **ekran iskeletini** taşıyor (165 satır). Kartlar
/// `analytics_charts.dart` (grafikler), durum ekranları + istatistik ızgarası
/// `analytics_views.dart`, hedefler ve yüzde hesabı `analytics_targets.dart`
/// altında. Bölme **yalnız taşıma** yaptı: hiçbir koşul, sabit veya metin
/// değişmedi (Satır satır doğrulandı).
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
    final targets = AnalyticsTargets.fromProfile(profile);
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
              // `AnalyticsAuthRequired` = "oturum yok", genel hata **değil**.
              // Repository bu durumu bilinçli olarak fırlatıyor (veri katmanı
              // "veri yok" ile "giriş yapmamış" ayrımını kendisi koruyor);
              // UI ayrımı yapmazsa kullanıcı giriş yapmamışken tüm grafikleri
              // "0 veri" gibi görür ve "Tekrar Gönder" butonu hiçbir işe
              // yaramaz (oturum yokken sorgu zaten çalışmıyor).
              error: (e, _) => e is AnalyticsAuthRequired
                  ? const AnalyticsSignInRequiredView()
                  : AnalyticsErrorView(
                      onRetry: () =>
                          ref.invalidate(analyticsDataProvider(locale)),
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
                      StatGrid(data: data, targets: targets),
                      const SizedBox(height: 16),
                      if (focus != null) ...[
                        FocusedMacroChartCard(
                          key: _focusChartKey,
                          data: data,
                          targets: targets,
                          period: period,
                          focus: focus,
                        ),
                        const SizedBox(height: 16),
                      ],
                      CaloriesChartCard(
                          data: data, targets: targets, period: period),
                      const SizedBox(height: 16),
                      MacrosChartCard(
                          data: data, targets: targets, period: period),
                      const SizedBox(height: 16),
                      MacroAveragesCard(data: data, targets: targets),
                      if (data.weightTrend.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        WeightTrendCard(data: data),
                      ],
                      const SizedBox(height: 16),
                      SummaryCard(data: data),
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
