import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/observability/app_logger.dart';
import '../../../data/models/meal_entry.dart';
import '../../../data/repositories/auth_repository.dart';
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
    // ⭐ A2r12: `custom_name` boşsa **kayıtlı ad** seed edilir (bkz. `_seedName`).
    _nameController.text = _seedName;
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

  /// Kaydet için: ad dolu **ve** miktar > 0. Miktar 0 iken tüm makrolar 0'a
  /// düşüyor ve kayıt sessizce bozuluyordu.
  ///
  /// ## ⭐ A2r12: bu koşul tek başına **"kayıt bozuk"** durumunu üretiyordu
  ///
  /// A4r11'in ölçtüğü (ve raporuna yazdığı) durum: topluluk/seed gıdasından
  /// eklenen öğünde `custom_name` **NULL** yazılır (`add_from_food_dialog:109`
  /// yalnız `isCustom || canDelete` için ad yazar) ve `foods` satırı silinirse
  /// `food_id` `ON DELETE SET NULL` olur. Sonuç: `food_id == null` **ve**
  /// `custom_name == null`.
  ///
  /// Ölçüm (A2r12, `test/features/add/edit_orphan_meal_a2r12_test.dart`):
  /// bu öğünü açan kullanıcı **boş bir ad alanı** görür, "Kaydet" düğmesi
  /// **kapalıdır** ve ekranda hangi yemeği düzenlediğini gösteren **hiçbir
  /// ipucu yoktur** — dashboard'da satır "Bilinmeyen" (`meal_entry.dart:89`).
  /// Kullanıcı adı nereden bulacak? Diyalog tek görevi bu satırı onarmaktı.
  ///
  /// Düzeltme: ad alanının **üstüne** `displayName` gösterilir ve boş
  /// `custom_name` bu değerle **seed** edilir. Böylece:
  /// - kullanıcı adı görür ve "düzenliyorum" der,
  /// - "Kaydet" **açılır** (miktar zaten `amount_g_ml`'den geliyor),
  /// - kaydetmek `custom_name`i doldurur → `displayName` düzelir.
  ///
  /// `displayName` `"Bilinmeyen"` ise (yani gerçekten ad yoksa) boş bırakılır:
  /// kullanıcıya `"Bilinmeyen"` adını yazdırmak veri uydurmak olurdu.
  bool get _valid =>
      _nameController.text.trim().isNotEmpty && _amount > 0;

  /// Ad alanının seed değeri — `custom_name` boşsa kayıtlı gıdanın adı.
  ///
  /// Ölçülen akış: `food_id` dolu ama `custom_name` NULL olan bir satır
  /// (A4r11'in topluluk gıdası yolu) düzenlendiğinde ekranda **hiçbir ad**
  /// görünmüyordu; bu değer onu kurtarır. `food_id` NULL ise (gıdası
  /// silinmiş ya da manuel girdi) yalnız `custom_name` vardır ve zaten
  /// seed edilmiştir.
  String get _seedName {
    final custom = widget.entry.customName;
    if (custom != null && custom.trim().isNotEmpty) return custom;
    // `displayName` `customName ?? 'Bilinmeyen'` — gerçek ad yoksa uydurma.
    final shown = widget.entry.displayName;
    return shown == _unknownFoodLabel ? '' : shown;
  }

  /// `meal_entry.dart`deki "Bilinmeyen" etiketinin **tek** karşılığı.
  ///
  /// İki yerde de sabit metin tutulması (model + dialog) iki doğruluk kaynağı
  /// üretirdi. Sabit metin **zaten** modelde tek yerde; buradaki eşleşme
  /// `MealEntry.displayName`'in ürettiği değerle yapılır, yani `custom_name`
  /// doluysa bu dal **hiç** çalışmaz.
  static const _unknownFoodLabel = 'Bilinmeyen';

  double get _amount => _parse(_amountController.text);

  ({double kcal, double protein, double carbs, double fat}) get _calc {
    final amount = _amount;
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
    final user = ref.read(currentUserProvider);
    if (user == null || !_valid || _saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final amount = _amount;
    final calc = _calc;

    try {
      await ref.read(diaryRepositoryProvider).updateMealEntry(
            user.id,
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
            // **İyimser kilit.** Kullanıcı iki ekranda (telefon + tablet) aynı
            // öğünü açtığında ikinci kaydetme, ilkinin değişikliklerini
            // sessizce eziyordu: kayıt "güncellendi" onayı veriyordu ama
            // kullanıcı ilk düzenlemenin miktarını kaybetmişti ve hiçbir iz
            // kalmıyordu. Ekranın gördüğü `updated_at` damgası verilir; DB'de
            // damga değişmişse yazma **hiç yapılmaz** ve
            // `MealEntryConflictError` fırlatılır (aşağıdaki ayrı kol).
            //
            // Damga `null` ise (eski satır / eksik kolon) kilit **devre dışı**
            // kalır → geriye dönük uyum, son yazan kazanır.
            expectedUpdatedAt: widget.entry.updatedAt,
          );
      ref.invalidate(dailyDataProvider);
      ref.invalidate(recentFoodsProvider);
      ref.invalidate(favoriteFoodsProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.edit.updated'.tr())),
      );
      if (mounted) Navigator.pop(context, true);
    } on ArgumentError catch (e, s) {
      // A2: `updateMealEntry` 0/NaN/Infinity miktar için `ArgumentError`
      // fırlatıyor (kısmi güncellemede `amount_g_ml` doğrulanıyor).
      AppLog.w('Geçersiz miktar — öğün güncellemesi reddedildi', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.invalidAmount'.tr())),
      );
      if (mounted) setState(() => _saving = false);
    } on MealEntryConflictError catch (e, s) {
      // A2: **kayıp güncelleme** kapandı. Kullanıcının ekranda gördüğü kayıt
      // başka bir cihazda değişmiş; bu yazma bilinçli olarak yapılmadı.
      // Genel hata mesajı ("Kayıt başarısız") yanlış olurdu: kullanıcı
      // kaydı **tekrar deneyerek** aynı kaybı yaşatabilirdi. Kilit
      // kaldırılmadan kaydetmeye çalışmak da yanlış — o yol birinci
      // düzenlemeyi ezerdi. Doğru davranış: dur, bildir, listeyi tazele.
      AppLog.w('Öğün çakışması — kayıt başka cihazda güncellenmiş', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.edit.conflict'.tr())),
      );
      // Sunucudaki hâli görmek için listeyi tazele (kullanıcı tekrar açtığında
      // güncel değerlerle karşılaşsın).
      ref.invalidate(dailyDataProvider);
      if (mounted) {
        setState(() => _saving = false);
        // Dialog'dan çık: ekrandaki değerler artık geçersiz, kullanıcının
        // yazdıklarını sessizce kaybetmesi yerine görünür biçimde kapatılır.
        Navigator.of(context).pop(false);
      }
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
                // ⭐ A2r12: `food_id` var ama `custom_name` boşsa (topluluk
                // gıdası, A4r11) alan **boş** görünür ve kullanıcı hangi
                // yemeği düzenlediğini bilmez. Kayıtlı ad burada gösterilir.
                helperText: _nameController.text.trim().isEmpty
                    ? 'dialogs.edit.nameMissing'.tr()
                    : null,
                helperMaxLines: 2,
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
              onChanged: (_) => setState(() {}),
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
