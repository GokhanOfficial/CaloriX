import 'dart:io';

import 'package:camera/camera.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uygulama içi kamera ekranı — barkod-tarayıcı benzeri tam ekran deneyim.
///
/// Akış (Faz 4 planı §1):
///  - Arka kamera + `ResolutionPreset.high` + flash toggle.
///  - Çekim butonu + galeriye geçiş + kapat.
///  - Çekim sonrası önizleme: "Yeniden Çek" / "Kullan".
///  - Sonuç: onaylanan görüntü `XFile` olarak döner (`Navigator.pop(context, file)`).
///
/// İzin reddedilirse boş döner; çağıran taraf native kameraya düşer.
class InAppCameraScreen extends StatefulWidget {
  /// Kamerayı açar; onaylanan `XFile`'ı döner (vazgeçilirse null).
  static Future<XFile?> show(BuildContext context) async {
    final cameras = await availableCameras();
    if (!context.mounted) return null;
    return Navigator.of(context).push<XFile>(
      MaterialPageRoute(
        builder: (_) => InAppCameraScreen.withCameras(cameras),
        fullscreenDialog: true,
      ),
    );
  }

  const InAppCameraScreen.withCameras(this._availableCameras, {super.key});

  final List<CameraDescription> _availableCameras;

  @override
  State<InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<InAppCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  FlashMode _flash = FlashMode.off;
  bool _ready = false;
  bool _capturing = false;
  XFile? _captured;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (widget._availableCameras.isEmpty) {
      setState(() => _error = 'chat.errors.load'.tr());
      return;
    }
    // Arka kamera tercih edilir.
    final desc = widget._availableCameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget._availableCameras.first,
    );

    _controller = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) setState(() => _ready = true);
    } on CameraException catch (e) {
      // İzin reddi veya donanım hatası — çağıran native'e düşer.
      if (mounted) setState(() => _error = e.description ?? 'common.error'.tr());
    }
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null) return;
    final next = _flash == FlashMode.off ? FlashMode.auto : FlashMode.off;
    try {
      await c.setFlashMode(next);
      setState(() => _flash = next);
    } on CameraException {
      // Cihaz desteklemiyorsa sessizce yok say.
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      if (mounted) setState(() => _captured = file);
    } on CameraException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.description ?? 'common.error'.tr())),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retake() => setState(() => _captured = null);

  void _use() {
    final file = _captured;
    if (file != null) Navigator.of(context).pop(file);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          child: _captured != null ? _preview(theme) : _viewfinder(isDark),
        ),
      ),
    );
  }

  /// Canlı kamera önizleme + çekim kontrolleri.
  Widget _viewfinder(bool isDark) {
    if (_error != null) {
      return _Message(
        icon: Icons.camera_alt_outlined,
        message: _error!,
        onRetry: () => Navigator.of(context).pop(null),
        retryLabel: 'common.close'.tr(),
      );
    }
    if (!_ready || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final c = _controller!;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(c)),
        // Üst bar: kapat + flash.
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CircleButton(
                  icon: Icons.close,
                  onTap: () => Navigator.of(context).pop(null),
                ),
                _CircleButton(
                  icon: _flash == FlashMode.off
                      ? Icons.flash_off
                      : Icons.flash_auto,
                  onTap: _toggleFlash,
                ),
              ],
            ),
          ),
        ),
        // Alt bar: çek butonu.
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: _ShutterButton(
              capturing: _capturing,
              onTap: _capture,
            ),
          ),
        ),
      ],
    );
  }

  /// Çekilen fotoğrafın onay ekranı.
  Widget _preview(ThemeData theme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(_captured!.path), fit: BoxFit.contain),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _retake,
                    icon: const Icon(Icons.cameraswitch_outlined),
                    label: Text('dialogs.retake'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _use,
                    icon: const Icon(Icons.check),
                    label: Text('dialogs.use'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.capturing, required this.onTap});

  final bool capturing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: capturing ? null : onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.3),
          border: Border.all(color: Colors.white, width: 4),
        ),
        alignment: Alignment.center,
        child: capturing
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            : Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
