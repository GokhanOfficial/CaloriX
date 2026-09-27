import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/observability/app_logger.dart';
import '../../core/updates/update_checker.dart';
import '../../core/updates/update_manifest.dart';
import '../../features/updates/force_update_page.dart';

/// Kök güncelleme kapısı — `MaterialApp.router` builder'ına sarılır.
///
/// - `required` → [ForceUpdatePage] uygulamanın yerine gösterilir (geçiş yok).
/// - `optional` → sürüm başına bir kez atlanabilir dialog (aynı oturumda
///   tekrar düşmez).
/// - `unknown` → tek seferlik "kontrol yapılamadı" uyarısı, uygulama açılır.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  bool _optionalDialogShown = false;
  bool _unknownWarningShown = false;

  /// `_maybeShowPrompts` yalnızca post-frame'de ve durum **değiştiğinde**
  /// çalışsın. Önceki sürüm `build()` içinde her frame'de
  /// `addPostFrameCallback` kaydediyordu: durum değişmese bile kuyruk
  /// büyüyor, uygulama arka plana alınınca biriken callback'ler çalışıp
  /// SnackBar/dialog göstermeye çalışıyordu.
  UpdateStatus? _lastHandledStatus;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(updateCheckerProvider.notifier).check());
  }

  Future<void> _maybeShowPrompts(UpdateStatus status) async {
    if (identical(status, _lastHandledStatus)) return;
    _lastHandledStatus = status;
    switch (status) {
      case UpdateOptional(:final manifest):
        if (_optionalDialogShown) return;
        if (await ref
            .read(updateCheckerProvider.notifier)
            .isDismissed(manifest.versionCode)) {
          return;
        }
        _optionalDialogShown = true;
        if (!mounted) return;
        await _showOptionalDialog(manifest);
      case UpdateUnknown():
        if (_unknownWarningShown) return;
        _unknownWarningShown = true;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('updates.checkFailed'.tr())),
        );
      default:
        break;
    }
  }

  Future<void> _showOptionalDialog(UpdateManifest manifest) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('updates.optionalTitle'.tr()),
        content: Text('updates.optionalBody'.tr(
          namedArgs: {'version': manifest.versionName},
        )),
        actions: [
          TextButton(
            onPressed: () {
              ref
                  .read(updateCheckerProvider.notifier)
                  .dismissOptional(manifest.versionCode);
              Navigator.of(dialogContext).pop();
            },
            child: Text('updates.later'.tr()),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _launchApk(manifest);
            },
            child: Text('updates.updateNow'.tr()),
          ),
        ],
      ),
    );
  }

  /// APK adresini açar.
  ///
  /// Manifest uzak sunucudan (GitHub Releases) geldiği için şema/uzantı
  /// doğrulanmadan `url_launcher`'a verilirse `javascript:` / `intent:` /
  /// `file:` gibi şemalar dış uygulamada açılabilir (açık yönlendirme /
  /// yerel dosya erişimi). `isApkUrlSafe` bu yüzden **zorunlu** kapıdır.
  ///
  /// `canLaunchUrl` **kullanılmaz**: Android'de tarayıcı/mağaza gibi bazı
  /// yönlendiriciler için yanlış negatif üretiyordu ve kullanıcı "Güncelle"
  /// dediğinde hiçbir şey olmuyordu. Doğrulama `launchUrl`'un kendi
  /// dönüş değeridir.
  Future<void> _launchApk(UpdateManifest manifest) async {
    if (!manifest.isApkUrlSafe) {
      AppLog.w('Güvensiz APK adresi reddedildi: ${manifest.apkUrl}');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(
      Uri.parse(manifest.apkUrl),
      mode: LaunchMode.externalApplication,
    );
    if (launched || !mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('updates.openFailed'.tr())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(updateCheckerProvider);
    if (!identical(status, _lastHandledStatus)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeShowPrompts(status),
      );
    }

    return switch (status) {
      UpdateRequired(:final manifest) => ForceUpdatePage(manifest: manifest),
      _ => widget.child,
    };
  }
}
