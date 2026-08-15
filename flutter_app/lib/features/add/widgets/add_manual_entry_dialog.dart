import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/food_repository.dart';

/// Manuel yiyecek girişi dialogu — web `AddMealDialog.tsx` karşılığı.
///
/// Tüm besin değerleri kullanıcı tarafından girilir; hesaplama yapılmaz.
/// `source: 'manual'`, `food_id: null` ile kaydedilir.
class AddManualEntryDialog extends ConsumerStatefulWidget {
  const AddManualEntryDialog({super.key, required this.defaultMealType});

  final MealType defaultMealType;

  /// Dialog'u gösterir; kaydedildiyse true döner.
  static Future<bool> show(
    BuildContext context, {
    required MealType defaultMealType,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: AddManualEntryDialog(defaultMealType: defaultMealType),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<AddManualEntryDialog> createState() =>
      _AddManualEntryDialogState();
}

class _AddManualEntryDialogState extends ConsumerState<AddManualEntryDialog> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();

  late MealType _mealType = widget.defaultMealType;
  bool _saving = false;

  /// Web parity: `parseFloat(x) || 0` — virgül girişini de kabul et.
  static double _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;

  bool get _valid => _nameController.text.trim().isNotEmpty;

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null || !_valid || _saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final date = ref.read(selectedDateProvider);

    try {
      await ref.read(diaryRepositoryProvider).addMealEntry(
            user.id,
            customName: _nameController.text.trim(),
            mealType: _mealType.name,
            amountGMl: _parse(_amountController.text),
            calculatedKcal: _parse(_kcalController.text),
            calculatedProtein: _parse(_proteinController.text),
            calculatedCarbs: _parse(_carbsController.text),
            calculatedFat: _parse(_fatController.text),
            entryDate: formatEntryDate(date),
          );
      ref.invalidate(dailyDataProvider);
      ref.invalidate(recentFoodsProvider);
      ref.invalidate(favoriteFoodsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('addFood.toasts.success'.tr())),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('addFood.toasts.error'.tr())),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _kcalController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'addFood.manual.title'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'dialogs.foodName'.tr(),
                hintText: 'dialogs.example'.tr(args: ['Tavuk Göğsü']),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MealType>(
              initialValue: _mealType,
              decoration: InputDecoration(
                labelText: 'addFood.meal'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final type in MealType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text('meals.${type.name}'.tr()),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _mealType = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
              ],
              decoration: InputDecoration(
                labelText: '${'dialogs.amount'.tr()} (g/ml)',
                hintText: '100',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MacroField(
                    controller: _kcalController,
                    label: 'dialogs.calories'.tr(),
                    suffix: 'kcal',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MacroField(
                    controller: _proteinController,
                    label: 'settings.goals.protein'.tr(),
                    suffix: 'g',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MacroField(
                    controller: _carbsController,
                    label: 'settings.goals.carbs'.tr(),
                    suffix: 'g',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MacroField(
                    controller: _fatController,
                    label: 'settings.goals.fat'.tr(),
                    suffix: 'g',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _valid && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text('dialogs.add'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroField extends StatelessWidget {
  const _MacroField({
    required this.controller,
    required this.label,
    required this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        hintText: '0',
        border: const OutlineInputBorder(),
      ),
    );
  }
}
