import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/diary_repository.dart';

/// Tarih seçici — web `DateSelector.tsx` karşılığı.
///
/// ‹ [Bugün/Dün/Yarın veya tarih] › + takvim seçici.
/// Geleceğe gitmeye izin verir (web ile aynı); "bugün" rozeti sadece
/// bugün dışındaki günlerde gösterilir.
class DateSelector extends ConsumerWidget {
  const DateSelector({super.key});

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _label(BuildContext context, DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_isSameDay(date, today)) return 'common.today'.tr();
    if (_isSameDay(date, today.subtract(const Duration(days: 1)))) {
      return 'common.yesterday'.tr();
    }
    if (_isSameDay(date, today.add(const Duration(days: 1)))) {
      return 'common.tomorrow'.tr();
    }
    // Ay adı aktif dile göre çevrilir (sabit 'd MMMM' → her dilde İngilizce).
    return DateFormat.yMMMMd(context.locale.languageCode).format(date);
  }

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final current = ref.read(selectedDateProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      ref.read(selectedDateProvider.notifier).state =
          DateTime(picked.year, picked.month, picked.day);
    }
  }

  void _shift(WidgetRef ref, int days) {
    final current = ref.read(selectedDateProvider);
    ref.read(selectedDateProvider.notifier).state =
        DateTime(current.year, current.month, current.day + days);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = ref.watch(selectedDateProvider);
    final now = DateTime.now();
    final isToday = _isSameDay(date, DateTime(now.year, now.month, now.day));

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'common.yesterday'.tr(),
          onPressed: () => _shift(ref, -1),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _pickDate(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 16),
                const SizedBox(width: 8),
                Text(
                  _label(context, date),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!isToday) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => ref
                        .read(selectedDateProvider.notifier)
                        .state = DateTime(now.year, now.month, now.day),
                    child: Text('common.today'.tr()),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'common.tomorrow'.tr(),
          onPressed: () => _shift(ref, 1),
        ),
      ],
    );
  }
}
