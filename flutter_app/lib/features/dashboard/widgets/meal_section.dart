import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/observability/app_logger.dart';
import '../../../data/models/meal_entry.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../add/widgets/add_with_ai_dialog.dart';
import '../../add/widgets/edit_meal_entry_dialog.dart';

/// Öğün grupları — web `Index.tsx`'teki MealSection karşılığı.
///
/// Her öğün (kahvaltı/öğle/akşam/atıştırma) bir kart; içinde girdiler,
/// öğün toplamı ve "ekle" butonu var.
class MealSections extends ConsumerWidget {
  const MealSections({super.key, required this.mealsByType});

  final Map<MealType, List<MealEntry>> mealsByType;

  /// Girdiyi soft-siler ve "Geri Al" SnackBar'ı gösterir. Kart yerinde
  /// kalır (Dismissible `confirmDismiss` false döner); geri al eylemi
  /// `restoreMealEntry` ile kaydı canlandırır.
  Future<void> _deleteEntry(
    BuildContext context,
    WidgetRef ref,
    MealEntry entry,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(diaryRepositoryProvider);
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      await repo.deleteMealEntry(user.id, entry.id);
      if (!context.mounted) return;
      ref.invalidate(dailyDataProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('dashboard.deletedSuccessfully'.tr()),
            action: SnackBarAction(
              label: 'common.undo'.tr(),
              onPressed: () async {
                try {
                  // `ref` dispose sonrası kullanılamaz; repository'yi önceden
                  // yakaladık, invalidate'i yalnızca widget yaşarken yap.
                  await repo.restoreMealEntry(user.id, entry.id);
                  if (!context.mounted) return;
                  ref.invalidate(dailyDataProvider);
                } catch (e, s) {
                  AppLog.e('Öğün girdisi geri alınamadı: ${entry.id}', e, s);
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    SnackBar(content: Text('dashboard.errorDelete'.tr())),
                  );
                }
              },
            ),
          ),
        );
    } catch (e, s) {
      AppLog.e('Öğün girdisi silinemedi: ${entry.id}', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text('dashboard.errorDelete'.tr())),
      );
    }
  }

  Future<void> _editEntry(
    BuildContext context,
    WidgetRef ref,
    MealEntry entry,
  ) async {
    final saved = await EditMealEntryDialog.show(context, entry: entry);
    if (saved && context.mounted) ref.invalidate(dailyDataProvider);
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
            onEdit: (entry) => _editEntry(context, ref, entry),
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
    required this.onEdit,
  });

  final MealType type;
  final String emoji;
  final List<MealEntry> entries;
  final Future<void> Function(MealEntry) onDelete;
  final ValueChanged<MealEntry> onEdit;

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
              onPressed: () =>
                  AddWithAiDialog.show(context, defaultMealType: type),
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
              // Kart yerinde kalsın, "Geri Al" SnackBar silmeyi aktif
              // eylesin — kullanıcı kaydırmayı görsel ipucu olarak kullanır.
              confirmDismiss: (_) async {
                await onDelete(entry);
                return false;
              },
              child: ListTile(
                dense: true,
                title: Text(entry.displayName),
                subtitle: Text('${entry.amountGMl.round()}g'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${entry.calculatedKcal.round()} kcal',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'dashboard.edit'.tr(),
                      onPressed: () => onEdit(entry),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'dashboard.delete'.tr(),
                      onPressed: () => onDelete(entry),
                    ),
                  ],
                ),
                onTap: () => onEdit(entry),
              ),
            ),
        ],
      ),
    );
  }
}
