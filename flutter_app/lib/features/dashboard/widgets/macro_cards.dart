import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Makro kartları — protein / karb / yağ (web `Index.tsx` macro grid).
class MacroCards extends StatelessWidget {
  const MacroCards({
    super.key,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.proteinTarget,
    required this.carbsTarget,
    required this.fatTarget,
  });

  final double protein;
  final double carbs;
  final double fat;
  final double proteinTarget;
  final double carbsTarget;
  final double fatTarget;

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
            color: Colors.redAccent,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MacroCard(
            labelKey: 'settings.goals.carbs',
            emoji: '🍞',
            value: carbs,
            target: carbsTarget,
            color: Colors.amber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MacroCard(
            labelKey: 'settings.goals.fat',
            emoji: '🥑',
            value: fat,
            target: fatTarget,
            color: Colors.lightBlue,
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
  });

  final String labelKey;
  final String emoji;
  final double value;
  final double target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = target > 0 ? (value / target).clamp(0.0, 1.0) : 0.0;

    return Card(
      child: Padding(
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
      ),
    );
  }
}
