import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/diary_repository.dart';

/// Su takibi — web `WaterTracker.tsx` karşılığı.
///
/// Toplam ml + ilerleme çubuğu + hızlı ekle (250/500) + özel miktar dialogu.
class WaterTracker extends ConsumerWidget {
  const WaterTracker({
    super.key,
    required this.current,
    required this.target,
  });

  final double current;
  final double target;

  Future<void> _addWater(
    BuildContext context,
    WidgetRef ref,
    double amount,
  ) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final date = ref.read(selectedDateProvider);
    try {
      await ref.read(diaryRepositoryProvider).addWaterEntry(
            user.id,
            amountMl: amount,
            entryDate: formatEntryDate(date),
          );
      ref.invalidate(dailyDataProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'dashboard.waterAdded'.tr(args: ['${amount.round()}']),
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('common.error'.tr())),
      );
    }
  }

  Future<void> _addCustom(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('dashboard.custom'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'ml'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: Text('common.save'.tr()),
          ),
        ],
      ),
    );
    if (amount != null && amount > 0 && context.mounted) {
      await _addWater(context, ref, amount);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final remaining = target - current;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('💧', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Text(
                  'dashboard.water'.tr(),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  '${current.round()} / ${target.round()} ml',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              remaining <= 0
                  ? 'dashboard.goalReached'.tr()
                  : 'dashboard.mlRemaining'
                      .tr(args: ['${remaining.round()}']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final amount in AppConstants.waterQuickAdd) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.water_drop, size: 18),
                      label: Text('+$amount'),
                      onPressed: () =>
                          _addWater(context, ref, amount.toDouble()),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.edit, size: 18),
                    label: Text('dashboard.custom'.tr()),
                    onPressed: () => _addCustom(context, ref),
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
