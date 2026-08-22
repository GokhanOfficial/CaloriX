import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(updateCheckerProvider.notifier).check());
  }

  Future<void> _maybeShowPrompts(UpdateStatus status) async {
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
              final url = Uri.parse(manifest.apkUrl);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Text('updates.updateNow'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(updateCheckerProvider);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowPrompts(status),
    );

    return switch (status) {
      UpdateRequired(:final manifest) => ForceUpdatePage(manifest: manifest),
      _ => widget.child,
    };
  }
}
