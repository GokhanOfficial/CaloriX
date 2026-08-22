import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Kalori halkası — web `Index.tsx`'teki dairesel ilerleme karşılığı.
///
/// Ortada kalan kalori (veya hedefe ulaşıldıysa 0) ve tüketilen/hedef özeti.
///
/// `onTap` verilirse halka tıklanır (dashboard → `/analytics`). Erişilebilirlik
/// için [InkWell] + `Semantics(button: true)` ile saranır.
class CalorieRing extends StatelessWidget {
  const CalorieRing({
    super.key,
    required this.consumed,
    required this.target,
    this.onTap,
  });

  final double consumed;
  final double target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    final remaining = math.max(0, target - consumed);
    final over = consumed > target;

    final ring = SizedBox(
      width: 180,
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: over
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${remaining.round()}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'dashboard.remaining'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${consumed.round()} / ${target.round()} kcal',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return ring;
    return Semantics(
      button: true,
      label: 'analytics.goToCalories'.tr(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(90),
        child: ring,
      ),
    );
  }
}
