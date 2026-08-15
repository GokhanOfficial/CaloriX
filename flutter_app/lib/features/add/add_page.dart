import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/food_item.dart';
import '../../data/repositories/food_repository.dart';
import 'widgets/add_from_food_dialog.dart';
import 'widgets/add_manual_entry_dialog.dart';
import 'widgets/add_with_ai_dialog.dart';
import 'widgets/barcode_scan_dialog.dart';

/// Arama girdisinin debounce edilmiş hâli (web `useFoodSearch` 300ms parity).
final _debouncedQueryProvider = StateProvider<String>((ref) => '');

/// Yemek ekleme sayfası — web `AddPage.tsx` karşılığı.
///
/// Bölümler (web ile aynı sıra): öğün seçici → AI aksiyonları →
/// son eklenenler → en çok yenenler → arama/barkod sekmeleri → manuel giriş.
class AddPage extends ConsumerStatefulWidget {
  const AddPage({super.key});

  @override
  ConsumerState<AddPage> createState() => _AddPageState();
}

class _AddPageState extends ConsumerState<AddPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  /// Web parity: `useState<MealType>("lunch")`.
  MealType _selectedMeal = MealType.lunch;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(_debouncedQueryProvider.notifier).state = value.trim();
    });
  }

  Future<void> _openFood(FoodItem food) async {
    await AddFromFoodDialog.show(
      context,
      food: food,
      defaultMealType: _selectedMeal,
    );
  }

  Future<void> _addWithAi() async {
    await AddWithAiDialog.show(context, defaultMealType: _selectedMeal);
  }

  Future<void> _scanBarcode() async {
    await BarcodeScanDialog.show(context, defaultMealType: _selectedMeal);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(_debouncedQueryProvider);
    final searching = query.length >= 2;

    return Scaffold(
      appBar: AppBar(title: Text('addFood.title'.tr())),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _MealSelector(
            value: _selectedMeal,
            onChanged: (type) => setState(() => _selectedMeal = type),
          ),
          const SizedBox(height: 12),
          _AiCard(onTap: _addWithAi),
          const SizedBox(height: 12),
          if (!searching) ...[
            _FoodListSection(
              title: 'addFood.recent.title'.tr(),
              icon: Icons.history,
              provider: recentFoodsProvider,
              emptyMessage: 'addFood.recent.empty'.tr(),
              onSelect: _openFood,
            ),
            const SizedBox(height: 12),
            _FoodListSection(
              title: 'addFood.favorites.title'.tr(),
              icon: Icons.star_outline,
              provider: favoriteFoodsProvider,
              emptyMessage: 'addFood.favorites.empty'.tr(),
              onSelect: _openFood,
            ),
            const SizedBox(height: 12),
          ],
          _SearchCard(
            controller: _searchController,
            onChanged: _onSearchChanged,
            query: query,
            onSelect: _openFood,
          ),
          const SizedBox(height: 12),
          _BarcodeCard(onTap: _scanBarcode),
          const SizedBox(height: 12),
          _ManualCard(
            onTap: () => AddManualEntryDialog.show(
              context,
              defaultMealType: _selectedMeal,
            ),
          ),
        ],
      ),
    );
  }
}

class _MealSelector extends StatelessWidget {
  const _MealSelector({required this.value, required this.onChanged});

  final MealType value;
  final ValueChanged<MealType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DropdownButtonFormField<MealType>(
          initialValue: value,
          decoration: InputDecoration(
            labelText: 'addFood.meal'.tr(),
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final type in MealType.values)
              DropdownMenuItem(
                value: type,
                child: Row(
                  children: [
                    Text(type.emoji),
                    const SizedBox(width: 8),
                    Text('meals.${type.name}'.tr()),
                  ],
                ),
              ),
          ],
          onChanged: (type) {
            if (type != null) onChanged(type);
          },
        ),
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'addFood.ai.title'.tr(),
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onTap,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'addFood.ai.buttonTitle'.tr(),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          'addFood.ai.buttonDesc'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yiyecek satırı — web `FoodListSection` içi button karşılığı:
/// ad + (marka) + `100g • X kcal`, sağda P/K/Y.
class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food, required this.onTap});

  final FoodItem food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = StringBuffer();
    if (food.brand != null && food.brand!.isNotEmpty) {
      subtitle.write('${food.brand}  ');
    }
    subtitle.write('100g • ${food.calories} kcal');

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      food.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      subtitle.toString(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _MacroLine(label: 'P', value: food.proteinG),
                  _MacroLine(label: 'K', value: food.carbsG),
                  _MacroLine(label: 'Y', value: food.fatG),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroLine extends StatelessWidget {
  const _MacroLine({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: ${_fmt(value)}g',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  /// Web parity: sayılar tam sayı ise ondalık gösterme (12.0 → "12").
  static String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

class _FoodListSection extends ConsumerWidget {
  const _FoodListSection({
    required this.title,
    required this.icon,
    required this.provider,
    required this.emptyMessage,
    required this.onSelect,
  });

  final String title;
  final IconData icon;
  final FutureProvider<List<FoodItem>> provider;
  final String emptyMessage;
  final ValueChanged<FoodItem> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncFoods = ref.watch(provider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            asyncFoods.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('common.error'.tr())),
              ),
              data: (foods) => foods.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          emptyMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final food in foods) ...[
                          _FoodTile(
                            food: food,
                            onTap: () => onSelect(food),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCard extends ConsumerWidget {
  const _SearchCard({
    required this.controller,
    required this.onChanged,
    required this.query,
    required this.onSelect,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String query;
  final ValueChanged<FoodItem> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final searching = query.length >= 2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'addFood.search.title'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: 'addFood.search.placeholder'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
            if (searching) ...[
              const SizedBox(height: 12),
              ref.watch(foodSearchProvider(query)).when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: Text('common.error'.tr())),
                    ),
                    data: (results) => results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                'addFood.search.noResults'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (final food in results) ...[
                                _FoodTile(
                                  food: food,
                                  onTap: () => onSelect(food),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                  ),
            ] else ...[
              const SizedBox(height: 24),
              Center(
                child: Column(
                  children: [
                    Text(
                      'addFood.search.promptTitle'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'addFood.search.promptDesc'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _BarcodeCard extends StatelessWidget {
  const _BarcodeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              'addFood.barcode.title'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 16),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.barcode_reader,
                size: 36,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'addFood.barcode.scanTitle'.tr(),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'addFood.barcode.scanDesc'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onTap,
              child: Text('addFood.barcode.openCamera'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualCard extends StatelessWidget {
  const _ManualCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.edit_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'addFood.manual.title'.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      'addFood.manual.desc'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
