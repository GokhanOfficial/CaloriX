import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../data/models/meal_entry.dart';
import '../../../data/repositories/diary_repository.dart';

/// Öğün grupları — web `Index.tsx`'teki MealSection karşılığı.
///
/// Her öğün (kahvaltı/öğle/akşam/atıştırma) bir kart; içinde girdiler,
/// öğün toplamı ve "ekle" butonu var.
class MealSections extends ConsumerWidget {
  const MealSections({super.key, required this.mealsByType});

  final Map<MealType, List<MealEntry>> mealsByType;

  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    MealEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(diaryRepositoryProvider).deleteMealEntry(entry.id);
      ref.invalidate(dailyDataProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('dashboard.deletedSuccessfully'.tr())),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('dashboard.errorDelete'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final type in MealType.values) ...[
          _MealCard(
            type: type,
            emoji: type.emoji,
            entries: mealsByType[type] ?? const [],
            onDelete: (entry) => _deleteEntry(context, ref, entry),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.type,
    required this.emoji,
    required this.entries,
    required this.onDelete,
  });

  final MealType type;
  final String emoji;
  final List<MealEntry> entries;
  final ValueChanged<MealEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kcal =
        entries.fold<double>(0, (sum, e) => sum + e.calculatedKcal);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Text(emoji, style: const TextStyle(fontSize: 20)),
            title: Text('meals.${type.name}'.tr()),
            subtitle: Text('${kcal.round()} kcal'),
            trailing: IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'dashboard.addFood'.tr(),
              onPressed: () => context.go(AppRoutes.add),
            ),
          ),
          if (entries.isNotEmpty) const Divider(height: 1),
          for (final entry in entries)
            Dismissible(
              key: ValueKey(entry.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: theme.colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              onDismissed: (_) => onDelete(entry),
              child: ListTile(
                dense: true,
                title: Text(entry.displayName),
                subtitle: Text('${entry.amountGMl.round()}g'),
                trailing: Text(
                  '${entry.calculatedKcal.round()} kcal',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
