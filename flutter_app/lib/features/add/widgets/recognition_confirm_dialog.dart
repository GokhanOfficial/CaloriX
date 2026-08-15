import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/recognized_food.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/food_repository.dart';

/// Tanıma sonucu onay ekranı — web `UnifiedFoodDialog` ("results" adımı).
///
/// Tüm tanınan yemekler TEK kaydırılabilir listede gösterilir; en üstte
/// ortak öğün seçici. Her yemek için düzenlenebilir: ad, miktar (g/ml),
/// 100g başına kcal/protein/carb/fat. Canlı toplam gösterilir.
/// Checkbox ile seçim kaldırılır (kaydet sırasında filtrelenir).
///
/// Kayıt (web `handleSave` parity):
///  - SEÇİLİ HER yemek için AYRI bir `meal_entries` INSERT (sıralı await).
///  - `source`: foto ise `"photo"`, metin ise `"text"`.
///  - `food_id`: HER ZAMAN null (tanıma akışında DB foods satırı oluşturulmaz).
///  - `custom_name`: yemek adı (boşsa `common.food`).
///  - `calculated_*`: round((per_100g/100)*amount).
///  - `photo_url`: hiçbir zaman ayarlanmaz (storage yükleme yok).
///  - Genişletilmiş besin değerleri yakalanır ama saklanmaz.
class RecognitionConfirmDialog extends StatelessWidget {
  const RecognitionConfirmDialog({
    super.key,
    required this.foods,
    required this.defaultMealType,
    required this.source,
    required this.description,
    this.onBack,
  });

  /// Tanıma yanıtı `foods[]`.
  final List<RecognizedFood> foods;

  final MealType defaultMealType;

  /// `"photo"` | `"text"` — `meal_entries.source` enum değeri.
  final String source;

  /// AI açıklaması (varsa üstte gösterilir).
  final String? description;

  /// Verilirse başlık satırında "geri" butonu gösterilir (yeniden analiz
  /// için AI giriş dialogunun results adımına gömüldüğünde kullanılır).
  /// Bağımsız `.show()` kullanımında (barkod) null kalır.
  final VoidCallback? onBack;

  /// Dialog'u gösterir; en az bir yemek kaydedildiyse true döner.
  static Future<bool> show(
    BuildContext context, {
    required List<RecognizedFood> foods,
    required MealType defaultMealType,
    required String source,
    String? description,
    VoidCallback? onBack,
  }) async {
    if (foods.isEmpty) return false;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: RecognitionConfirmBody(
          foods: foods,
          defaultMealType: defaultMealType,
          source: source,
          description: description,
          onBack: onBack,
          onSaved: (saved) => Navigator.of(context).pop(saved),
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return RecognitionConfirmBody(
      foods: foods,
      defaultMealType: defaultMealType,
      source: source,
      description: description,
      onBack: onBack,
      onSaved: (saved) => Navigator.of(context).pop(saved),
    );
  }
}

/// Onay içeriği — hem bağımsız dialog hem de AI giriş dialogunun results
/// adımında gömülü kullanılır. Kayıt başarılı olunda [onSaved] `true` ile
/// çağrılır; çağıran dialog kendi Navigator.pop'unu yönetir.
class RecognitionConfirmBody extends ConsumerStatefulWidget {
  const RecognitionConfirmBody({
    super.key,
    required this.foods,
    required this.defaultMealType,
    required this.source,
    required this.onSaved,
    this.description,
    this.onBack,
  });

  final List<RecognizedFood> foods;
  final MealType defaultMealType;
  final String source;
  final String? description;
  final VoidCallback? onBack;

  /// Kayıt tamamlandığında `true`, başarısız/iptal `false` ile çağrılır.
  final ValueChanged<bool> onSaved;

  @override
  ConsumerState<RecognitionConfirmBody> createState() =>
      _RecognitionConfirmBodyState();
}

/// Listedeki tek yemeğin düzenlenebilir durumu.
class _FoodRow {
  _FoodRow(this.food)
      : name = food.name,
        amount = food.amountGMl > 0 ? food.amountGMl : 100,
        calories = food.caloriesPer100G,
        protein = food.proteinGPer100G,
        carbs = food.carbsGPer100G,
        fat = food.fatGPer100G,
        confidence = food.confidence ?? 70,
        selected = true;

  final RecognizedFood food;
  String name;
  double amount;
  double calories;
  double protein;
  double carbs;
  double fat;
  double confidence;
  bool selected;
}

class _RecognitionConfirmBodyState
    extends ConsumerState<RecognitionConfirmBody> {
  late MealType _mealType;
  late final List<_FoodRow> _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _mealType = widget.defaultMealType;
    _rows = widget.foods.map(_FoodRow.new).toList();
  }

  int get _selectedCount => _rows.where((r) => r.selected).length;

  ({int kcal, double protein, double carbs, double fat}) _rowCalc(_FoodRow r) {
    final kcal = (r.calories * r.amount / 100).round();
    return (
      kcal: kcal,
      protein: _round1(r.protein * r.amount / 100),
      carbs: _round1(r.carbs * r.amount / 100),
      fat: _round1(r.fat * r.amount / 100),
    );
  }

  ({int kcal, double protein, double carbs, double fat}) get _total {
    var kcal = 0, p = 0.0, c = 0.0, f = 0.0;
    for (final r in _rows) {
      if (!r.selected) continue;
      final v = _rowCalc(r);
      kcal += v.kcal;
      p += v.protein;
      c += v.carbs;
      f += v.fat;
    }
    return (kcal: kcal, protein: p, carbs: c, fat: f);
  }

  static double _round1(double v) => (v * 10).round() / 10;

  Future<void> _save() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _saving || _selectedCount == 0) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final date = ref.read(selectedDateProvider);
    final entryDate = formatEntryDate(date);

    final selected = _rows.where((r) => r.selected).toList();
    var added = 0;

    try {
      // Web parity: seçili her yemek için sıralı ayrı INSERT.
      for (final r in selected) {
        final calc = _rowCalc(r);
        await ref.read(diaryRepositoryProvider).addMealEntry(
              user.id,
              mealType: _mealType.name,
              amountGMl: r.amount,
              calculatedKcal: calc.kcal.toDouble(),
              calculatedProtein: calc.protein,
              calculatedCarbs: calc.carbs,
              calculatedFat: calc.fat,
              entryDate: entryDate,
              source: widget.source,
              foodId: null, // tanıma: her zaman null
              customName: r.name.trim().isEmpty
                  ? 'common.food'.tr()
                  : r.name.trim(),
              note: null,
              photoUrl: null, // tanıma akışında hiçbir zaman ayarlanmaz
            );
        added++;
      }

      ref.invalidate(dailyDataProvider);
      ref.invalidate(recentFoodsProvider);
      ref.invalidate(favoriteFoodsProvider);

      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.foodsAdded'.tr(args: ['$added']))),
      );
      widget.onSaved(true);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.saveFailed'.tr())),
      );
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _total;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.onBack != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: Text('dialogs.back'.tr()),
                  ),
                ),
              Text(
                'dialogs.recognizedFoods'.tr(),
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (widget.description != null &&
                  widget.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  widget.description!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 12),
              // Ortak öğün seçici (web: tek shared meal-type).
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
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _rowTile(theme, _rows[i]),
                ),
              ),
              const SizedBox(height: 12),
              // Toplam (seçili yemekler).
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Macro(label: 'kcal', value: '${total.kcal}'),
                      _Macro(
                        label: 'P',
                        value: '${total.protein.toStringAsFixed(1)}g',
                      ),
                      _Macro(
                        label: 'K',
                        value: '${total.carbs.toStringAsFixed(1)}g',
                      ),
                      _Macro(
                        label: 'Y',
                        value: '${total.fat.toStringAsFixed(1)}g',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _selectedCount > 0 && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text('dialogs.foodAdded'.tr(args: ['$_selectedCount'])),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowTile(ThemeData theme, _FoodRow r) {
    final calc = _rowCalc(r);
    return Opacity(
      opacity: r.selected ? 1.0 : 0.6,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Checkbox(
                  value: r.selected,
                  onChanged: (v) => setState(() => r.selected = v ?? false),
                ),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: r.name),
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      labelText: 'dialogs.foodName'.tr(),
                    ),
                    onChanged: (v) {
                      r.name = v;
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _NumField(
                    label: 'dialogs.amount'.tr(),
                    suffix: 'g/ml',
                    value: r.amount,
                    onChanged: (v) => setState(() => r.amount = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MiniNum(
                        label: 'dialogs.calPer100g'.tr(),
                        value: r.calories,
                        onChanged: (v) => setState(() => r.calories = v),
                      ),
                      _MiniNum(
                        label: 'dialogs.proPer100g'.tr(),
                        value: r.protein,
                        onChanged: (v) => setState(() => r.protein = v),
                      ),
                      _MiniNum(
                        label: 'dialogs.carbPer100g'.tr(),
                        value: r.carbs,
                        onChanged: (v) => setState(() => r.carbs = v),
                      ),
                      _MiniNum(
                        label: 'dialogs.fatPer100g'.tr(),
                        value: r.fat,
                        onChanged: (v) => setState(() => r.fat = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'dialogs.confidence'.tr(args: [r.confidence.toStringAsFixed(0)]),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '${calc.kcal} kcal · '
                  'P ${calc.protein.toStringAsFixed(1)} · '
                  'K ${calc.carbs.toStringAsFixed(1)} · '
                  'Y ${calc.fat.toStringAsFixed(1)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
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

/// Miktar için tam genişlikli sayı alanı.
class _NumField extends StatelessWidget {
  const _NumField({
    required this.label,
    required this.suffix,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String suffix;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: _format(value)),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) {
        final n = double.tryParse(v);
        if (n != null) onChanged(n);
      },
    );
  }
}

/// 100g başına makro için küçük sayı alanı (Wrap içinde).
class _MiniNum extends StatelessWidget {
  const _MiniNum({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: TextField(
        controller: TextEditingController(text: _format(value)),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) {
          final n = double.tryParse(v);
          if (n != null) onChanged(n);
        },
      ),
    );
  }
}

String _format(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
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
