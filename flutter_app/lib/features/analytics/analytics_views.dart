/// Analitik sayfasının **durum görünümleri ve istatistik ızgarası** —
/// `analytics_page.dart`'den bölündü (A4r6, Tur 6).
///
/// Buradaki üç ekran "veri varken" / "hata varken" / "oturum yokken"
/// ayrımını taşır. `_StatGrid` dört istatistik kartını 2×2 ızgarada gösterir
/// ve web renk kurallarını (±%90 kalori bandı, su/protein alt sınırı) birebir
/// uygular.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/analytics_repository.dart';
import 'analytics_targets.dart';

// ===========================================================================
// Hata durumu — retry butonu (dashboard `_ErrorBody` ile aynı davranış).
// ===========================================================================
class AnalyticsErrorView extends StatelessWidget {
  const AnalyticsErrorView({required this.onRetry, super.key});

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

// ===========================================================================
// Oturum yok durumu — "giriş yap" çağrısı (genel hata ekranından AYRI).
// ===========================================================================

/// Analitik verisi için oturum bulunamadığında gösterilir.
///
/// "Hata + Tekrar Gönder" yanlış olurdu: `analyticsDataProvider` oturum yoksa
/// sorguya gitmeden `AnalyticsAuthRequired` fırlattığı için yeniden denemek
/// aynı sonucu verir ve kullanıcı gerçek sorunu (oturum) aramak zorunda
/// kalır. Bunun yerine oturum ekranına yönlendiren bir buton gösterilir.
class AnalyticsSignInRequiredView extends StatelessWidget {
  const AnalyticsSignInRequiredView({super.key});

  /// Çeviri anahtarı eksikse ham anahtarı (`analytics.signInRequired`)
  /// göstermemek için Türkçe metne düşer.
  ///
  /// `easy_localization` çeviri bulunamazsa **ham anahtarı** döndürür
  /// (`EasyLocalization.tr` → `Translations.get` → `null` → anahtar); bu
  /// yüzden dönen metin anahtarla karşılaştırılır.
  static String get _signInRequiredText {
    const key = 'analytics.signInRequired';
    final translated = key.tr();
    if (translated != key) return translated;
    return 'Analitik verilerini görmek için giriş yap';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              // `analytics.signInRequired` çevirisi 12 dil dosyasına
              // A6r3 tarafından eklendi. Anahtar yine de yoksa
              // easy_localization ham anahtarı (`analytics.signInRequired`)
              // ekrana basar; `hasKey` ile bu durumda Türkçe metne
              // düşülüyor (çeviri dosyası eksikken bile anlaşılır arayüz).
              _signInRequiredText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.auth),
              icon: const Icon(Icons.login),
              label: Text('auth.signIn'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// 4 istatistik kartı (web renk kuralları parity)
// ===========================================================================
class StatGrid extends StatelessWidget {
  const StatGrid({required this.data, required this.targets, super.key});

  final AnalyticsData data;
  final AnalyticsTargets targets;

  @override
  Widget build(BuildContext context) {
    final avg = data.averages;

    // Hedef 0/NaN olabilir (bozuk profil satırı) → bölmeden 0 döndür.
    final calPercent = analyticsPercent(avg.avgCalories, targets.calories);
    final waterPercent = analyticsPercent(avg.avgWater, targets.water);
    final proteinPercent = analyticsPercent(avg.avgProtein, targets.protein);

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
