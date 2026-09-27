import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/updates/update_checker.dart';
import '../../../core/updates/update_manifest.dart';

/// Zorunlu güncelleme ekranı — uygulama bu sürümüyle çalışamaz.
///
/// Tek çıkış yolu "Güncelle" (APK tarayıcıda açılır); "Yeniden kontrol et"
/// ağ geri geldiğinde kararı tazeler.
class ForceUpdatePage extends ConsumerWidget {
  const ForceUpdatePage({super.key, required this.manifest});

  final UpdateManifest manifest;

  Future<void> _openApk(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // `apkUrl` uzak manifestten (GitHub Releases `latest.json`) gelir ve
    // doğrudan `url_launcher`'a verilir. Doğrulamasız hâlde `javascript:`,
    // `intent:`, `file:`, `content:` şemaları cihazdaki başka uygulamaya
    // açılabilir (açık yönlendirme / yerel dosya erişimi). A3'ün
    // `UpdateManifest.isSafeApkUrl` süzgeci (https + `.apk` + userInfo yok)
    // zorunlu kapıdır — `update_gate.dart` aynı süzgeci uygular, burada
    // ekranın kendi çıkış yolu da aynı kapıdan geçmeli.
    if (!manifest.isApkUrlSafe) {
      debugPrint(
        'ForceUpdatePage: güvensiz apkUrl reddedildi '
        '(scheme=${manifest.apkUrl.split(':').first})',
      );
      messenger.showSnackBar(
        SnackBar(content: Text('updates.unsafeUrl'.tr())),
      );
      return;
    }

    final url = Uri.parse(manifest.apkUrl.trim());
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('updates.openFailed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notes = manifest.notesFor(context.locale.languageCode);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.system_update_alt,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 20),
                Text('updates.requiredTitle'.tr(),
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'updates.requiredBody'.tr(
                    namedArgs: {'version': manifest.versionName},
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('updates.notesTitle'.tr(),
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(notes, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: Text('updates.updateNow'.tr()),
                    onPressed: () => _openApk(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      ref.read(updateCheckerProvider.notifier).check(),
                  child: Text('updates.recheck'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
