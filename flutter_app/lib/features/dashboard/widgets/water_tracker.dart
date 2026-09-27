import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/observability/app_logger.dart';
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
      // Await sırasında widget dispose olabilir — `ref.invalidate` dispose
      // sonrası "Bad state: Cannot use "ref" after the widget was disposed"
      // fırlatır ve alttaki catch bunu bir insert hatası sanıp yanıltıcı
      // "Hata" toast'u gösterir. Dispose olduysa invalidate'i atla; başarılı
      // kayıt zaten günlük veriyi yeniden yükleyen sayfayı yeniden canlandırınca
      // görünür olacak.
      if (context.mounted) {
        ref.invalidate(dailyDataProvider);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              // JSON `dashboard.waterAdded` named placeholder `{amount}`
              // kullanır; `.tr(namedArgs:)` ile substitute edilir (positional
              // `args` boş `{}` bekler, literal `{amount}` gösterilirdi).
              'dashboard.waterAdded'
                  .tr(namedArgs: {'amount': '${amount.round()}'}),
            ),
          ),
        );
      }
    } catch (e, s) {
      AppLog.e('Su kaydı eklenemedi (${amount.round()} ml)', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text('common.error'.tr())),
      );
    }
  }

  Future<void> _addCustom(BuildContext context, WidgetRef ref) async {
    // Controller dialogun kendi State'inde — dışarıda yaratılıp bırakılan
    // controller bellek sızdırıyordu.
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => const _WaterInputDialog(),
    );
    if (amount != null && amount > 0 && amount <= 5000 && context.mounted) {
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
                  : 'dashboard.mlRemaining'.tr(
                      namedArgs: {'amount': '${remaining.round()}'},
                    ),
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

/// Özel su miktarı giriş dialogu — controller'ı kendi State'inde tutar.
class _WaterInputDialog extends StatefulWidget {
  const _WaterInputDialog();

  @override
  State<_WaterInputDialog> createState() => _WaterInputDialogState();
}

class _WaterInputDialogState extends State<_WaterInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('dashboard.custom'.tr()),
      content: TextField(
        controller: _controller,
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
              Navigator.pop(context, double.tryParse(_controller.text)),
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}
