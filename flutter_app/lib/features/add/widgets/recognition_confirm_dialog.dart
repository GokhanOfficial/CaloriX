import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/observability/app_logger.dart';
import '../../../data/models/recognized_food.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/food_repository.dart';
import '../../../shared/widgets/number_fields.dart';
import 'meal_selector.dart';

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
  /// Bağımsız `.show()` kullanımında null kalır.
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
///
/// Controller'lar [_FoodRowTileState] içinde稳定 tutulur; her tuş
/// vuruşunda yeniden yaratılmaz → odak kaybı yok (eski sürümde `build`
/// içinde `TextEditingController(text:)` yaratılıyordu, bu odak
/// kaybına ve controller sızıntısına yol açıyordu).
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

  /// Kaydedilebilecek seçili satır sayısı (uyarı metni ve `_save` filtresi
  /// ile aynı ölçüt).
  int get _selectedCount => _rows
      .where((r) => r.selected && DiaryRepository.isUsableAmount(r.amount))
      .length;

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
      // Aynı tek doğruluk kaynağı (uyarı metni de bunu kullanıyor).
      if (!r.selected || !DiaryRepository.isUsableAmount(r.amount)) continue;
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
    if (user == null || _saving) return;

    // Miktarı kullanılamaz (0/negatif/NaN/Infinity) satırlar kaydedilmez —
    // 0 gamlık kayıt günlüğü bozar. Uyarı metniyle **aynı** ölçüt
    // (`isUsableAmount`) kullanılır, böylece "uyarı yok" görülen satır
    // kaydedilemez hale gelmez.
    //
    // **Önce** seçim kontrolü, **sonra** `_saving = true`: önce `setState`
    // yapılırsa bu erken dönüş `_saving`'i `true` bırakıyor ve Kaydet butonu
    // (`onPressed: _selectedCount > 0 && !_saving`) kalıcı olarak kilitleniyor
    // — kullanıcı butona tekrar basamıyor, ekran kilitleniyor.
    final selected = _rows
        .where((r) => r.selected && DiaryRepository.isUsableAmount(r.amount))
        .toList();
    if (selected.isEmpty) return;

    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final date = ref.read(selectedDateProvider);
    final entryDate = formatEntryDate(date);

    var added = 0;

    try {
      // Webparity: seçili her yemek için sıralı ayrı INSERT.
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
        SnackBar(
          content: Text(
            'dialogs.foodsAdded'.tr(namedArgs: {'count': '$added'}),
          ),
        ),
      );
      widget.onSaved(true);
    } on ArgumentError catch (e, s) {
      // A2: `addMealEntry` NaN/Infinity/≤0 miktar için `ArgumentError`
      // fırlatıyor. Kısmi kayıtta (bazı satırlar eklendi) kullanıcıya
      // yalnızca "geçersiz miktar" demek yanıltıcı olurdu; eklenen sayı
      // da belirtilir.
      AppLog.w('Geçersiz miktar — tanıma kaydı reddedildi', e, s);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            added == 0
                ? 'dialogs.invalidAmount'.tr()
                : 'dialogs.invalidAmountPartial'.tr(
                    namedArgs: {'count': '$added'},
                  ),
          ),
        ),
      );
      if (mounted) setState(() => _saving = false);
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
              MealSegmentedButton(
                value: _mealType,
                onChanged: (value) => setState(() => _mealType = value),
              ),
              const SizedBox(height: 12),
              // Toplam (seçili yemekler) — listenin üstünde sabit.
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
              // Tanınan yemekler — her satır kendi State'inde controller
              // tutar (odak kaybı fix). ValueKey ile parent rebuild
              // sırasında element korunur.
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    return _FoodRowTile(
                      key: ValueKey('food-row-$i-${r.food.name}'),
                      row: r,
                      onChanged: () => setState(() {}), // toplamı yenile
                    );
                  },
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
                label: Text(
                  'dialogs.foodAdded'.tr(
                    namedArgs: {'count': '$_selectedCount'},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tek bir tanınan yemek satırı — State içinde稳定 controller'lar.
///
/// Odak kaybı fix: eski sürümde `_rowTile` metodu her `build`'da yeni
/// `TextEditingController` yaratıyordu; parent `setState` (her tuşta)
/// tüm ListView'i yeniden mount ediyor → controller yeniden yaratılıyor
/// → odak kaybı. Artık controller'lar `initState`'te bir kez yaratılır,
/// `dispose`'da bırakılır; `ValueKey` ile parent rebuild sırasında
/// element + State korunur.
class _FoodRowTile extends StatefulWidget {
  const _FoodRowTile({super.key, required this.row, required this.onChanged});

  final _FoodRow row;

  /// Satır alanı değiştiğinde parent'ı total'i yeniden hesaplaması için.
  final VoidCallback onChanged;

  @override
  State<_FoodRowTile> createState() => _FoodRowTileState();
}

class _FoodRowTileState extends State<_FoodRowTile> {
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _calController;
  late final TextEditingController _proteinController;
  late final TextEditingController _carbsController;
  late final TextEditingController _fatController;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _nameController = TextEditingController(text: r.name);
    _amountController = TextEditingController(text: formatAmount(r.amount));
    _calController =
        TextEditingController(text: formatAmount(r.calories));
    _proteinController =
        TextEditingController(text: formatAmount(r.protein));
    _carbsController = TextEditingController(text: formatAmount(r.carbs));
    _fatController = TextEditingController(text: formatAmount(r.fat));

    void notify() => widget.onChanged();
    _nameController.addListener(() {
      widget.row.name = _nameController.text;
      notify();
    });
    // Sayısal alanlar: geçersiz parse ise row'u güncelleme (kullanıcı
    // yazıyor olabilir — ara durumlar), geçerli ise güncelle + parent'a haber ver.
    _amountController.addListener(() {
      final n = double.tryParse(_amountController.text);
      if (n != null) {
        widget.row.amount = n;
        notify();
      }
    });
    _calController.addListener(() {
      final n = double.tryParse(_calController.text);
      if (n != null) {
        widget.row.calories = n;
        notify();
      }
    });
    _proteinController.addListener(() {
      final n = double.tryParse(_proteinController.text);
      if (n != null) {
        widget.row.protein = n;
        notify();
      }
    });
    _carbsController.addListener(() {
      final n = double.tryParse(_carbsController.text);
      if (n != null) {
        widget.row.carbs = n;
        notify();
      }
    });
    _fatController.addListener(() {
      final n = double.tryParse(_fatController.text);
      if (n != null) {
        widget.row.fat = n;
        notify();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _calController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.row;
    final calc = (
      kcal: (r.calories * r.amount / 100).round(),
      protein: (r.protein * r.amount / 10).round() / 10,
      carbs: (r.carbs * r.amount / 10).round() / 10,
      fat: (r.fat * r.amount / 10).round() / 10,
    );

    return Opacity(
      opacity: r.selected ? 1.0 : 0.6,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Üst satır: seçim + yemek adı.
              Row(
                children: [
                  Checkbox(
                    value: r.selected,
                    onChanged: (v) {
                      setState(() => r.selected = v ?? false);
                      widget.onChanged();
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        isDense: true,
                        border: const OutlineInputBorder(),
                        labelText: 'dialogs.foodName'.tr(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Miktar — belirgin, tam genişlik. 0 girilirse kayıt 0amlık
              // olurdu; bu yüzden hem uyarı hem de satırı kayıttan çıkarma.
              NumField(
                controller: _amountController,
                label: 'dialogs.amount'.tr(),
                suffix: 'g/ml',
              ),
              // Uyarı koşulu `_total`'ın/kaydetme filtresinin **tek doğruluk
              // kaynağı** (`DiaryRepository.isUsableAmount`) ile aynı olmalı:
              // iki dal ayrışırsa kullanıcı "uyarı yok" dediğinde satır
              // yine de kaydedilmiyor, ya da tersi. `isUsableAmount` NaN ve
              // Infinity'yi de eler (`r.amount <= 0` ikisini de *kabul* eder).
              //
              // Metin `dialogs.amountRequired` ("Miktar gerekli") değil
              // `dialogs.invalidAmount` ("Geçerli bir miktar girin"):
              // 250 yazıp ondalık noktasını unutan kullanıcı "girilmedi"
              // mesajı alıyordu, yani ekranda ne yaptığını anlamıyordu.
              // `invalidAmount` 12 dilde **zaten var** → 0 çeviri işi
              // (bkz. `diary_repository.dart:105-117`).
              if (!DiaryRepository.isUsableAmount(r.amount))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'dialogs.invalidAmount'.tr(),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              // 100g başına makrolar — tek satırda 4 eşit kompakt alan
              // (eski Wrap/2×2 yerine, daha düzenli).
              Row(
                children: [
                  Expanded(
                    child: MiniNumField(
                      controller: _calController,
                      label: 'dialogs.calPer100g'.tr(),
                      width: double.infinity,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: MiniNumField(
                      controller: _proteinController,
                      label: 'dialogs.proPer100g'.tr(),
                      width: double.infinity,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: MiniNumField(
                      controller: _carbsController,
                      label: 'dialogs.carbPer100g'.tr(),
                      width: double.infinity,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: MiniNumField(
                      controller: _fatController,
                      label: 'dialogs.fatPer100g'.tr(),
                      width: double.infinity,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Alt satır: güven + toplam.
              Row(
                children: [
                  Text(
                    'dialogs.confidence'.tr(
                      namedArgs: {
                        'percent': r.confidence.toStringAsFixed(0),
                      },
                    ),
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
