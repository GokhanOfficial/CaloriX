import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/camera_preference.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/recognized_food.dart';
import '../../../data/repositories/recognition_repository.dart';
import 'in_app_camera_screen.dart';
import 'recognition_confirm_dialog.dart';

/// AI ile yemek ekleme dialogu — web `UnifiedFoodDialog`'un giriş adımı.
///
/// Akış (Faz 4 planı §1 + §2/§3):
///  1. **Giriş**: foto çek (kamera tercihine göre in_app/native), galeriden
///     seç, veya metin gir. "AI ile analiz et" butonu.
///  2. **Yükleniyor**: edge fonksiyonu çağrılır (`recognize-food` /
///     `recognize-food-text`).
///  3. **Sonuç**: [RecognitionConfirmBody] gömülü; `source` foto ise `"photo"`,
///     metin ise `"text"`. Geri butonu → giriş adımına dön (yeniden analiz).
///
/// Kamera tercihi (`cameraPreferenceProvider`):
///  - `inApp` → [InAppCameraScreen] (barkod-tarayıcı benzeri tam ekran).
///    İzin reddedilirse boş döner → native `ImagePicker.camera`'a düşer.
///  - `native` → doğrudan `ImagePicker.camera` (telefon kamera uygulaması).
class AddWithAiDialog extends ConsumerStatefulWidget {
  const AddWithAiDialog({super.key, required this.defaultMealType});

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
        child: AddWithAiDialog(defaultMealType: defaultMealType),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<AddWithAiDialog> createState() => _AddWithAiDialogState();
}

enum _Step { input, loading, results }

class _AddWithAiDialogState extends ConsumerState<AddWithAiDialog> {
  final _textController = TextEditingController();
  final _imagePicker = ImagePicker();
  XFile? _photo;
  bool _analyzing = false;
  String? _error;
  _Step _step = _Step.input;
  RecognitionResult? _result;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _canAnalyze => _photo != null || _textController.text.trim().isNotEmpty;

  Future<void> _pickFromCamera() async {
    final pref = ref.read(cameraPreferenceProvider);
    XFile? file;

    if (pref == CameraPreference.inApp) {
      // Önce uygulama içi kamera; izin reddedilirse native'e düş.
      file = await InAppCameraScreen.show(context);
      if (file == null && mounted) file = await _imagePicker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
    } else {
      file = await _imagePicker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
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

  Future<void> _analyze() async {
    if (!_canAnalyze || _analyzing) return;
    final hasPhoto = _photo != null;
    final text = _textController.text.trim();

    setState(() {
      _step = _Step.loading;
      _analyzing = true;
      _error = null;
    });

    try {
      final repo = ref.read(recognitionRepositoryProvider);
      final result = hasPhoto
          ? await repo.recognizeFood(_photo!, additionalText: text.isEmpty ? null : text)
          : await repo.recognizeFoodText(text);

      if (!mounted) return;
      if (result.foods.isEmpty) {
        setState(() {
          _step = _Step.input;
          _analyzing = false;
          _error = 'dialogs.noResults'.tr();
        });
        return;
      }
      setState(() {
        _result = result;
        _step = _Step.results;
        _analyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.input;
        _analyzing = false;
        _error = 'dialogs.analysisFailed'.tr();
      });
    }
  }

  void _backToInput() {
    setState(() {
      _step = _Step.input;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: switch (_step) {
            _Step.input => _inputStep(theme),
            _Step.loading => _loadingStep(theme),
            _Step.results => _resultsStep(theme),
          },
        ),
      ),
    );
  }

  Widget _inputStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'dialogs.whatDidYouEat'.tr(),
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // Foto önizleme / çekim butonları.
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_photo!.path),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.restaurant_menu,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 12),
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
            controller: _textController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'dialogs.additionalInfo'.tr(),
              hintText: 'dialogs.photoAdditionalHint'.tr(),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (!_canAnalyze) ...[
            const SizedBox(height: 8),
            Text(
              'dialogs.textOrPhotoRequired'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _canAnalyze && !_analyzing ? _analyze : null,
            icon: const Icon(Icons.auto_awesome),
            label: Text('dialogs.analyzeWithAI'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _loadingStep(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'dialogs.aiAnalyzing'.tr(),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _resultsStep(ThemeData theme) {
    final result = _result;
    if (result == null) return const SizedBox.shrink();

    return RecognitionConfirmBody(
      foods: result.foods,
      defaultMealType: widget.defaultMealType,
      source: _photo != null ? 'photo' : 'text',
      description: result.description,
      onBack: _backToInput,
      onSaved: (saved) {
        if (mounted) Navigator.of(context).pop(saved);
      },
    );
  }
}
