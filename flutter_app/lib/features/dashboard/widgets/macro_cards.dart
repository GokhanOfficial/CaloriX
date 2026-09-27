import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../analytics/macro_focus.dart';
import '../../../core/theme/app_theme.dart';

/// Makro kartları — protein / karb / yağ (web `Index.tsx` macro grid).
///
/// Her kart tıklanır; `onMacroTap` verilirse dashboard →
/// `/analytics?macro=<name>` derin bağlantısı tetiklenir ve seçili makro için
/// per-macro takip grafiği açılır. Renkler `AppColors.macro*` ile tema parity.
class MacroCards extends StatelessWidget {
  const MacroCards({
    super.key,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
    this.onMacroTap,
  });

  final double protein;
  final double carbs;
  final double fat;
  final double proteinTarget;
  final double carbsTarget;
  final double fatTarget;

  /// Makro kartına tıklanınca — `MacroFocus` ile analitik sayfasına bağla.
  final void Function(MacroFocus)? onMacroTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MacroCard(
            labelKey: 'settings.goals.protein',
            emoji: '🥩',
            value: protein,
            target: proteinTarget,
            color: AppColors.macroProtein,
            onTap: onMacroTap == null
                ? null
                : () => onMacroTap!(MacroFocus.protein),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MacroCard(
            labelKey: 'settings.goals.carbs',
            emoji: '🍞',
            value: carbs,
            target: carbsTarget,
            color: AppColors.macroCarbs,
            onTap: onMacroTap == null
                ? null
                : () => onMacroTap!(MacroFocus.carbs),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MacroCard(
            labelKey: 'settings.goals.fat',
            emoji: '🥑',
            value: fat,
            target: fatTarget,
            color: AppColors.macroFat,
            onTap: onMacroTap == null
                ? null
                : () => onMacroTap!(MacroFocus.fat),
          ),
        ),
      ],
    );
  }
}

class _MacroCard extends StatelessWidget {
  const _MacroCard({
    required this.labelKey,
    required this.emoji,
    required this.value,
    required this.target,
    required this.color,
    this.onTap,
  });

  final String labelKey;
  final String emoji;
  final double value;
  final double target;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = target > 0 ? (value / target).clamp(0.0, 1.0) : 0.0;

    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  labelKey.tr(),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${value.round()}g',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            '/ ${target.round()}g',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
            color: color,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );

    if (onTap == null) return Card(child: content);
    return Semantics(
      button: true,
      label: '$labelKey.tr() ${value.round()} / ${target.round()} g',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
