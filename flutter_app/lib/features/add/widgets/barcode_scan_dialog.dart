import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/config/camera_preference.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/barcode_food.dart';
import '../../../data/models/recognized_food.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/barcode_repository.dart';
import '../../../data/repositories/diary_repository.dart';
import '../../../data/repositories/food_repository.dart';
import '../../../data/repositories/recognition_repository.dart';
import 'in_app_camera_screen.dart';

/// Barkod ile yemek ekleme dialogu — web `BarcodeScanDialog.tsx` karşılığı.
///
/// Adımlar (web ile aynı: `scan` → `analyzing` → `notFound` / `result`):
///  1. **scan**: `MobileScanner` ile canlı barkod tarama (native) + manuel
///     barkod giriş alanı. Web'de yalnızca manuel giriş (mobile_scanner web
///     eklentisi olmasına rağmen plan manueli tercih eder).
///  2. **analyzing**: barkod DB'de aranır (`lookupByBarcode`).
///  3. **notFound**: DB'de yoksa kullanıcı fotoğraf (kamera tercihine göre
///     in_app/native) veya ek metin girer; AI ile analiz edilir
///     (`recognize-food` / `recognize-food-text`, prompt'a barkod gömülü).
///  4. **result**: düzenlenebilir ad/marka/miktar/porsiyon/100g makrolar +
///     açılır-kapanır genişletilmiş besin + canlı hesap önizleme + öğün
///     seçici. Kayıt → (gerekirse) `createFoodWithNutrition` + `addMealEntry`.
///
/// Kayıt (web `handleSave` parity):
///  - DB'den değilse (`!fromDb`) ve barkod varsa: önce yeni `foods` +
///    `food_nutrition` satırı (`createFoodWithNutrition`), `finalFoodId` alınır.
///  - Tek `meal_entries` INSERT: `source` = foto varsa `"photo"`, yoksa `"barcode"`;
///    `food_id` = `finalFoodId` (DB yemeği ise mevcut id); `custom_name` = displayName;
///    `calculated_*` = round(per100/100*amount).
class BarcodeScanDialog extends ConsumerStatefulWidget {
  const BarcodeScanDialog({super.key, required this.defaultMealType});

  final MealType defaultMealType;

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
        child: BarcodeScanDialog(defaultMealType: defaultMealType),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<BarcodeScanDialog> createState() => _BarcodeScanDialogState();
}

enum _Step { scan, analyzing, notFound, result }

class _BarcodeScanDialogState extends ConsumerState<BarcodeScanDialog> {
  final _manualController = TextEditingController();
  final _additionalController = TextEditingController();
  final _imagePicker = ImagePicker();
  MobileScannerController? _scannerController;

  _Step _step = _Step.scan;
  bool _busy = false; // analyzing veya kaydediyor
  String? _error;
  String? _barcodeValue; // taramadan/manuelden gelen barkod
  XFile? _photo; // notFound adımında ürün etiketi fotoğrafı
  BarcodeFood? _food;

  @override
  void dispose() {
    _manualController.dispose();
    _additionalController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  // --- Barkod tarama (scan adımı) ---

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code != null && code.isNotEmpty) {
      _scannerController?.stop();
      _lookupBarcode(code);
    }
  }

  void _manualSearch() {
    final code = _manualController.text.trim();
    if (code.isEmpty) return;
    _lookupBarcode(code);
  }

  // --- DB arama (analyzing) ---

  Future<void> _lookupBarcode(String code) async {
    setState(() {
      _step = _Step.analyzing;
      _busy = true;
      _barcodeValue = code;
      _error = null;
    });

    try {
      final food = await ref.read(barcodeRepositoryProvider).lookupByBarcode(code);
      if (!mounted) return;
      if (food != null) {
        setState(() {
          _food = food;
          _step = _Step.result;
          _busy = false;
        });
      } else {
        // DB'de yok → kullanıcı fotoğraf/metin ile AI'a yönlendir.
        setState(() {
          _food = null;
          _step = _Step.notFound;
          _busy = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _food = null;
        _step = _Step.notFound;
        _busy = false;
        _error = 'dialogs.barcode.productNotFound'.tr();
      });
    }
  }

  // --- notFound: fotoğraf/metin ile AI analizi ---

  Future<void> _pickFromCamera() async {
    final pref = ref.read(cameraPreferenceProvider);
    XFile? file;

    if (pref == CameraPreference.inApp) {
      file = await InAppCameraScreen.show(context);
      if (file == null && mounted) {
        file = await _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          imageQuality: 85,
        );
      }
    } else {
      file = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 85,
      );
    }

    if (file != null) setState(() => _photo = file);
  }

  Future<void> _pickFromGallery() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file != null) setState(() => _photo = file);
  }

  Future<void> _analyzeWithAi() async {
    final hasPhoto = _photo != null;
    final additional = _additionalController.text.trim();
    if (!hasPhoto && additional.isEmpty) {
      setState(() => _error = 'dialogs.barcode.aiPromptRequired'.tr());
      return;
    }

    setState(() {
      _step = _Step.analyzing;
      _busy = true;
      _error = null;
    });

    try {
      final repo = ref.read(recognitionRepositoryProvider);
      final RecognitionResult result;

      if (hasPhoto) {
        // Web parity: `additional_text: additional || "Barkod: ${barcodeValue}"`.
        result = await repo.recognizeFood(
          _photo!,
          additionalText: additional.isEmpty
              ? 'dialogs.barcode.barcodeLabel'.tr(args: ['$_barcodeValue'])
              : additional,
        );
      } else {
        // Web parity: metin akışında barkod istemi gömülü.
        final prompt = additional.isEmpty
            ? 'dialogs.barcode.aiTextPrompt'.tr(args: ['$_barcodeValue'])
            : additional;
        result = await repo.recognizeFoodText(prompt);
      }

      if (!mounted) return;
      if (result.foods.isEmpty) {
        setState(() {
          _step = _Step.notFound;
          _busy = false;
          _error = 'dialogs.analysisFailed'.tr();
        });
        return;
      }
      setState(() {
        _food = BarcodeFood.fromRecognizedFood(
          result.foods.first,
          _barcodeValue,
        );
        _step = _Step.result;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _step = _Step.notFound;
        _busy = false;
        _error = 'dialogs.analysisFailed'.tr();
      });
    }
  }

  void _backToScan() {
    _scannerController?.start();
    setState(() {
      _step = _Step.scan;
      _food = null;
      _photo = null;
      _error = null;
      _additionalController.clear();
    });
  }

  void _reScan() => _backToScan();

  // --- Kayıt (result adımı) ---

  Future<void> _save() async {
    final food = _food;
    final user = ref.read(currentUserProvider);
    if (food == null || user == null || _busy) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final date = ref.read(selectedDateProvider);
    final entryDate = formatEntryDate(date);
    // Fotoğraf varsa kaynak photo, yoksa barcode (web parity).
    final source = _photo != null ? 'photo' : 'barcode';

    try {
      String? finalFoodId = food.foodId; // DB yemeği ise dolu

      // DB'de olmayan + barkodu olan ürün: önce foods+nutrition satırı.
      if (!food.fromDb && _barcodeValue != null && _barcodeValue!.isNotEmpty) {
        finalFoodId = await ref
            .read(barcodeRepositoryProvider)
            .createFoodWithNutrition(
              userId: user.id,
              food: food,
              source: source,
            );
      }

      final calc = food.forAmount(food.amountGMl);
      await ref.read(diaryRepositoryProvider).addMealEntry(
            user.id,
            mealType: _mealType.name,
            amountGMl: food.amountGMl,
            calculatedKcal: calc.kcal.toDouble(),
            calculatedProtein: calc.protein,
            calculatedCarbs: calc.carbs,
            calculatedFat: calc.fat,
            entryDate: entryDate,
            source: source,
            foodId: finalFoodId,
            customName: food.displayName,
            note: null,
            photoUrl: null,
          );

      ref.invalidate(dailyDataProvider);
      ref.invalidate(recentFoodsProvider);
      ref.invalidate(favoriteFoodsProvider);

      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.foodAdded'.tr(args: ['1']))),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text('dialogs.saveFailed'.tr())),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  late MealType _mealType;

  @override
  void initState() {
    super.initState();
    _mealType = widget.defaultMealType;
    // native'te tarayıcıyı başlat; web'de manuel giriş kullanılır.
    if (!kIsWeb) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        returnImage: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: switch (_step) {
            _Step.scan => _scanStep(theme),
            _Step.analyzing => _analyzingStep(theme),
            _Step.notFound => _notFoundStep(theme),
            _Step.result => _resultStep(theme),
          },
        ),
      ),
    );
  }

  // --- scan ---

  Widget _scanStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'dialogs.barcode.title'.tr(),
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Öğün seçici (web: scan adımında mevcut).
          _MealSelector(
            value: _mealType,
            onChanged: (v) => setState(() => _mealType = v),
          ),
          const SizedBox(height: 12),
          // Kamera görünümü: native'te canlı tarayıcı, web'de yer tutucu.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: kIsWeb
                  ? Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          Icons.barcode_reader,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : MobileScanner(
                      controller: _scannerController,
                      onDetect: _onDetect,
                      fit: BoxFit.cover,
                      errorBuilder: (_, error, _) => _ScannerError(
                        message: error.errorDetails?.message ??
                            'dialogs.barcode.cameraError'.tr(),
                        onRetry: () => _scannerController?.start(),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'dialogs.barcode.scanDesc'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'dialogs.barcode.manualEntry'.tr(),
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'dialogs.barcode.manualPlaceholder'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _manualSearch(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _manualController.text.trim().isEmpty
                    ? null
                    : _manualSearch,
                child: Text('dialogs.barcode.search'.tr()),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  // --- analyzing ---

  Widget _analyzingStep(ThemeData theme) {
    final searchingDb = _barcodeValue != null && _food == null && _photo == null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            searchingDb
                ? 'dialogs.barcode.searching'.tr()
                : 'dialogs.aiAnalyzing'.tr(),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (_barcodeValue != null) ...[
            const SizedBox(height: 4),
            Text(
              'dialogs.barcode.barcodeLabel'.tr(args: ['$_barcodeValue']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- notFound ---

  Widget _notFoundStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.search_off,
                  size: 40,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  'dialogs.barcode.productNotFound'.tr(),
                  style: theme.textTheme.titleMedium,
                ),
                if (_barcodeValue != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'dialogs.barcode.barcodeLabel'.tr(args: ['$_barcodeValue']),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'dialogs.barcode.productNotFoundDesc'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // Fotoğraf önizleme / çekim butonları.
          if (_photo != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    File(_photo!.path),
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filled(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _photo = null),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFromCamera,
                    icon: const Icon(Icons.camera_alt),
                    label: Text('dialogs.takePhoto'.tr()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_outlined),
                    label: Text('dialogs.selectFromGallery'.tr()),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _additionalController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'dialogs.additionalInfo'.tr(),
              hintText: 'dialogs.barcode.aiPrompt'.tr(),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _backToScan,
                  child: Text('dialogs.back'.tr()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_photo != null ||
                          _additionalController.text.trim().isNotEmpty) &&
                          !_busy
                      ? _analyzeWithAi
                      : null,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text('dialogs.analyzeWithAI'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- result ---

  Widget _resultStep(ThemeData theme) {
    final food = _food;
    if (food == null) return const SizedBox.shrink();

    final calc = food.forAmount(food.amountGMl);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'dialogs.barcode.title'.tr(),
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // Durum rozeti: DB'den bulundu / AI güveni.
          if (food.fromDb)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'dialogs.barcode.foundInDb'.tr(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            )
          else if (food.confidence != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  'dialogs.confidence'.tr(
                    args: [food.confidence!.toStringAsFixed(0)],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
          if (_barcodeValue != null) ...[
            const SizedBox(height: 4),
            Text(
              'dialogs.barcode.barcodeLabel'.tr(args: ['$_barcodeValue']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          _MealSelector(
            value: _mealType,
            onChanged: (v) => setState(() => _mealType = v),
          ),
          const SizedBox(height: 12),
          // Düzenlenebilir ad.
          TextField(
            controller: TextEditingController(text: food.name),
            decoration: InputDecoration(
              labelText: 'dialogs.foodName'.tr(),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => food.name = v),
          ),
          const SizedBox(height: 8),
          // Marka (opsiyonel).
          TextField(
            controller: TextEditingController(text: food.brand ?? ''),
            decoration: InputDecoration(
              labelText: 'dialogs.barcode.brand'.tr(),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => food.brand = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _NumField(
                  label: 'dialogs.amount'.tr(),
                  suffix: 'g/ml',
                  value: food.amountGMl,
                  onChanged: (v) => setState(() => food.amountGMl = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NumField(
                  label: 'dialogs.barcode.servingSize'.tr(),
                  suffix: 'g',
                  value: food.servingSizeG ?? food.amountGMl,
                  onChanged: (v) => setState(() => food.servingSizeG = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.edit, size: 12, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                'dialogs.barcode.per100gHint'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 100g ana makrolar.
          Row(
            children: [
              Expanded(
                child: _MiniNum(
                  label: 'dialogs.calPer100g'.tr(),
                  value: food.calories,
                  onChanged: (v) => setState(() => food.calories = v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MiniNum(
                  label: 'dialogs.proPer100g'.tr(),
                  value: food.proteinG,
                  onChanged: (v) => setState(() => food.proteinG = v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MiniNum(
                  label: 'dialogs.carbPer100g'.tr(),
                  value: food.carbsG,
                  onChanged: (v) => setState(() => food.carbsG = v),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _MiniNum(
                  label: 'dialogs.fatPer100g'.tr(),
                  value: food.fatG,
                  onChanged: (v) => setState(() => food.fatG = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Genişletilmiş besin — açılır-kapanır (web <details>).
          _ExtendedNutrition(
            food: food,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          // Hesaplanan değer önizlemesi.
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    '${'dialogs.calculatedValues'.tr()} '
                        '(${food.amountGMl.toStringAsFixed(0)}g)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
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
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reScan,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text('dialogs.barcode.reScan'.tr()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: !_busy ? _save : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text('dialogs.save'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barkod dialogunda paylaşılan öğün seçici.
class _MealSelector extends StatelessWidget {
  const _MealSelector({required this.value, required this.onChanged});

  final MealType value;
  final ValueChanged<MealType> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<MealType>(
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
    );
  }
}

/// Tarama hatası yer tutucusu — kamera izin/donanım reddi.
class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.camera_alt_outlined,
                  size: 40, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text('dialogs.barcode.tryAgain'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Genişletilmiş besin değerleri — açılır-kapanır bölüm (web `<details>`).
/// Değerler `BarcodeFood` üzerinde doğrudan düzenlenir (nullable).
class _ExtendedNutrition extends StatefulWidget {
  const _ExtendedNutrition({required this.food, required this.onChanged});

  final BarcodeFood food;
  final VoidCallback onChanged;

  @override
  State<_ExtendedNutrition> createState() => _ExtendedNutritionState();
}

class _ExtendedNutritionState extends State<_ExtendedNutrition> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = widget.food;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                'dialogs.barcode.extendedNutrition'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _OptNum(
                  label: 'dialogs.barcode.saturatedFat'.tr(),
                  value: f.saturatedFatG,
                  onChanged: (v) {
                    f.saturatedFatG = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptNum(
                  label: 'dialogs.barcode.transFat'.tr(),
                  value: f.transFatG,
                  onChanged: (v) {
                    f.transFatG = v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _OptNum(
                  label: 'dialogs.barcode.sugars'.tr(),
                  value: f.sugarsG,
                  onChanged: (v) {
                    f.sugarsG = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptNum(
                  label: 'dialogs.fiberG'.tr(),
                  value: f.fiberG,
                  onChanged: (v) {
                    f.fiberG = v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _OptNum(
            label: 'dialogs.barcode.salt'.tr(),
            value: f.saltG,
            onChanged: (v) {
              f.saltG = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _OptNum(
                  label: 'dialogs.barcode.novaScore'.tr(),
                  value: f.novaScore?.toDouble(),
                  isInt: true,
                  onChanged: (v) {
                    f.novaScore = v?.round();
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptText(
                  label: 'dialogs.barcode.nutriScore'.tr(),
                  value: f.nutriScore,
                  onChanged: (v) {
                    f.nutriScore = v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ],
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

/// 100g başına makro için küçük sayı alanı.
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
      width: 72,
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

/// Opsiyonel (nullable) genişletilmiş besin alanı — boş değer kabul edilir.
class _OptNum extends StatelessWidget {
  const _OptNum({
    required this.label,
    required this.value,
    required this.onChanged,
    this.isInt = false,
  });

  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;
  final bool isInt;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? ''
        : isInt
            ? value!.round().toString()
            : _format(value!);
    return TextField(
      controller: TextEditingController(text: text),
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
        if (v.isEmpty) {
          onChanged(null);
          return;
        }
        final n = double.tryParse(v);
        if (n != null) onChanged(n);
      },
    );
  }
}

/// Nutri-Score için tek karakterli metin alanı (A-E).
class _OptText extends StatelessWidget {
  const _OptText({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: value ?? ''),
      maxLength: 1,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) => onChanged(v.isEmpty ? null : v.toUpperCase()),
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
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

String _format(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}
