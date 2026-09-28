import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/observability/app_logger.dart';
import '../../../data/models/food_item.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/food_repository.dart';
import '../../../shared/widgets/favorite_button.dart';
import 'meal_selector.dart';

/// Seçili yemeği miktar + öğün seçerek günlüğe ekleme dialogu.
/// Web `AddFromFoodDialog.tsx` karşılığı — hesaplama formülleri aynı:
/// kcal = round(cal/100 * amount), makrolar 1 ondalık.
class AddFromFoodDialog extends ConsumerStatefulWidget {
  const AddFromFoodDialog({
    super.key,
    required this.food,
    required this.defaultMealType,
  });

  final FoodItem food;
  final MealType defaultMealType;

  /// Dialog'u gösterir; kaydedildiyse true döner.
  static Future<bool> show(
    BuildContext context, {
    required FoodItem food,
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
        child: AddFromFoodDialog(food: food, defaultMealType: defaultMealType),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<AddFromFoodDialog> createState() => _AddFromFoodDialogState();
}

class _AddFromFoodDialogState extends ConsumerState<AddFromFoodDialog> {
  late final TextEditingController _amountController;
  late MealType _mealType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: (widget.food.servingSizeG ?? 100).round().toString(),
    );
    _mealType = widget.defaultMealType;
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// Virgül girişini de kabul et (`add_manual_entry_dialog` parity).
  double get _amount =>
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final date = ref.read(selectedDateProvider);
    final calc = widget.food.forAmount(_amount);

    try {
      await ref.read(diaryRepositoryProvider).addMealEntry(
            user.id,
            foodId: widget.food.foodId,
            // ⭐ P0 (A4r11): `custom_name` "adı yedekle" görevi görür.
            //
            // `meal_entries.food_id` FK'si `ON DELETE SET NULL`
            // (`full_setup.sql` / `20260927120000`): kullanıcı gıdasını
            // sildiğinde öğün satırı **korunur** ama `food_id` NULL olur.
            // `fetchDaily` `foods` join'i **yapmaz** (düz `select()`), yani
            // `MealEntry.displayName` (`meal_entry.dart:89`) yalnızca
            // `custom_name`'e bakar → NULL ise dashboard'da **"Bilinmeyen"**.
            // Kalorisi duran ama adı olmayan bir öğün = veri kaybı gibi görünür.
            //
            // Kural: `isCustom` (elle/tanıma girdisi, `food_id` zaten NULL)
            // **veya** `canDelete` (kullanıcının kendi gıdası, silinebilir)
            // → ad yazılır. `canDelete == false` olan topluluk/seed gıdası
            // silinemez (`created_by = auth.uid()` reddi) → FK hiç kırılmaz →
            // `custom_name` **gereksiz tekrardır** (yazılmaz).
            //
            // Ölçüm: `canDelete` = `created_by == userId`; `deleteFood` ile
            // **birebir** aynı koşul (bkz. `food_repository.dart:24-63`). Yani
            // "adı yaz" ile "gıda silinebilir" aynı sorunun iki yüzü.
            customName: (widget.food.isCustom || widget.food.canDelete)
                ? widget.food.name
                : null,
            mealType: _mealType.name,
            amountGMl: _amount,
            calculatedKcal: calc.kcal.toDouble(),
            calculatedProtein: calc.protein,
            calculatedCarbs: calc.carbs,
            calculatedFat: calc.fat,
            entryDate: formatEntryDate(date),
          );
      ref.invalidate(dailyDataProvider);
      ref.invalidate(recentFoodsProvider);
      ref.invalidate(favoriteFoodsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'dashboard.addedToMeal'.tr(
              namedArgs: {
                'food': widget.food.name,
                'meal': 'meals.${_mealType.name}'.tr(),
              },
            ),
          ),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ArgumentError catch (e, s) {
      // A2: `addMealEntry` NaN/Infinity/≤0 miktar veya negatif makro için
      // `ArgumentError` fırlatıyor; DB'ye hiç yazılmıyor.
      AppLog.w('Geçersiz miktar reddedildi (${widget.food.name})', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.invalidAmount'.tr())),
      );
      if (mounted) setState(() => _saving = false);
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
    final calc = widget.food.forAmount(_amount);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.food.name,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (widget.food.brand != null)
              Text(
                widget.food.brand!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            // Favori yıldızı — yemek seçim ekranında da favorileyebilmek için.
            // `custom` girdilerde `foodId == null` olduğundan düğme **gizlenir**
            // (`favorite_foods.food_id` NOT NULL FK).
            Align(
              alignment: Alignment.centerRight,
              child: FavoriteButton(
                foodId: widget.food.foodId,
                foodName: widget.food.name,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              // Ondalık giriş mümkündü (`food.forAmount` double bekliyor) ama
              // `digitsOnly` noktayı filtreleyip 12.5 → 125'e dönüştürüyordu.
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
              ],
              decoration: InputDecoration(
                labelText: 'dialogs.amount'.tr(),
                suffixText: 'g/ml',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            MealSegmentedButton(
              value: _mealType,
              onChanged: (value) => setState(() => _mealType = value),
            ),
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _Macro(label: 'kcal', value: '${calc.kcal}'),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _amount > 0 && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text('addFood.title'.tr()),
            ),
          ],
        ),
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
