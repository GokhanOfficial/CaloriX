import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/meal_entry.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/food_repository.dart';
import '../../../shared/widgets/number_fields.dart';
import 'meal_selector.dart';

/// Mevcut yemek girdisini düzenleme dialogu — web `EditEntryDialog` karşılığı.
///
/// `MealEntry` toplam (`calculated_*`) değerleri saklar; açılışta per-100g
/// geri hesaplanır: `per100 = calculated / amount * 100`. Kullanıcı amount veya
/// per-100g değerlerini düzenler; kayıtta yeni `calculated_*` =
/// `round(per100/100 * amount)` ile `updateMealEntry`'e yazılır.
///
/// Controller'lar `initState`'te seed edilir, `dispose`'da bırakılır — her
/// tuşta odak kaybı yok (şablon: `add_manual_entry_dialog.dart`).
class EditMealEntryDialog extends ConsumerStatefulWidget {
  const EditMealEntryDialog({super.key, required this.entry});

  final MealEntry entry;

  /// Dialog'u gösterir; güncellendiyse true döner (caller dashboard'u
  /// invalidate eder).
  static Future<bool> show(
    BuildContext context, {
    required MealEntry entry,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: EditMealEntryDialog(entry: entry),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<EditMealEntryDialog> createState() =>
      _EditMealEntryDialogState();
}

class _EditMealEntryDialogState extends ConsumerState<EditMealEntryDialog> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _kcalController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();

  late MealType _mealType;
  bool _saving = false;

  /// `x`'ten 100g'ye normalize: `calculated / amount * 100`.
  static double _per100(double calculated, double amount) {
    if (amount <= 0) return 0;
    return calculated / amount * 100;
  }

  /// Virgül girişini de kabul et (`add_manual_entry_dialog` parity).
  static double _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _nameController.text = e.customName ?? '';
    _amountController.text = formatAmount(e.amountGMl);
    _kcalController.text = formatAmount(_per100(e.calculatedKcal, e.amountGMl));
    _proteinController.text =
        formatAmount(_per100(e.calculatedProtein, e.amountGMl));
    _carbsController.text =
        formatAmount(_per100(e.calculatedCarbs, e.amountGMl));
    _fatController.text = formatAmount(_per100(e.calculatedFat, e.amountGMl));
    _mealType = MealType.values.asNameMap()[e.mealType] ?? MealType.snack;
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

  bool get _valid => _nameController.text.trim().isNotEmpty;

  ({double kcal, double protein, double carbs, double fat}) get _calc {
    final amount = _parse(_amountController.text);
    final k = (_parse(_kcalController.text) * amount / 100);
    final p = (_parse(_proteinController.text) * amount / 100);
    final c = (_parse(_carbsController.text) * amount / 100);
    final f = (_parse(_fatController.text) * amount / 100);
    return (
      kcal: k,
      protein: p,
      carbs: c,
      fat: f,
    );
  }

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final amount = _parse(_amountController.text);
    final calc = _calc;

    try {
      await ref.read(diaryRepositoryProvider).updateMealEntry(
            widget.entry.id,
            {
              'custom_name': _nameController.text.trim(),
              'meal_type': _mealType.name,
              'amount_g_ml': amount,
              'calculated_kcal': calc.kcal,
              'calculated_protein': calc.protein,
              'calculated_carbs': calc.carbs,
              'calculated_fat': calc.fat,
              // source/food_id/photo_url/entry_date korunur.
            },
          );
      ref.invalidate(dailyDataProvider);
      ref.invalidate(recentFoodsProvider);
      ref.invalidate(favoriteFoodsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.edit.updated'.tr())),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calc = _calc;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'dialogs.edit.title'.tr(),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'dialogs.foodName'.tr(),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            MealSegmentedButton(
              value: _mealType,
              onChanged: (value) => setState(() => _mealType = value),
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
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'dialogs.per100g'.tr(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MacroField(
                    controller: _kcalController,
                    label: 'dialogs.calPer100g'.tr(),
                    suffix: 'kcal',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MacroField(
                    controller: _proteinController,
                    label: 'dialogs.proPer100g'.tr(),
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
                    label: 'dialogs.carbPer100g'.tr(),
                    suffix: 'g',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MacroField(
                    controller: _fatController,
                    label: 'dialogs.fatPer100g'.tr(),
                    suffix: 'g',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Macro(label: 'kcal', value: '${calc.kcal.round()}'),
                    _Macro(
                      label: 'P',
                      value: '${calc.protein.toStringAsFixed(1)}g',
                    ),
                    _Macro(
                      label: 'K',
                      value: '${calc.carbs.toStringAsFixed(1)}g',
                    ),
                    _Macro(
                      label: 'Y',
                      value: '${calc.fat.toStringAsFixed(1)}g',
                    ),
                  ],
                ),
              ),
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
                  : const Icon(Icons.check),
              label: Text('dialogs.edit.updated'.tr()),
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

class _Macro extends StatelessWidget {
  const _Macro({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
