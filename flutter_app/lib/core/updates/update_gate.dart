import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/updates/apk_downloader.dart';
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

  /// APK indirme/doğrulama sürüyor — ikinci kez tıklamayı engeller.
  /// (Zorunlu güncellemede `ForceUpdatePage` kendi butonunu yönetir.)
  bool _busy = false;

  /// `_maybeShowPrompts` yalnızca post-frame'de ve durum **değiştiğinde**
  /// çalışsın. Önceki sürüm `build()` içinde her frame'de
  /// `addPostFrameCallback` kaydediyordu: durum değişmese bile kuyruk
  /// büyüyor, uygulama arka plana alınınca biriken callback'ler çalışıp
  /// SnackBar/dialog göstermeye çalışıyordu.
  UpdateStatus? _lastHandledStatus;

  /// Bu frame için bir post-frame istemi zaten kuyruğa alınmış mı?
  ///
  /// `_maybeShowPrompts` async olduğu için `_lastHandledStatus` yalnızca
  /// callback **çalıştığında** güncellenir. Durum arka arkaya iki kez
  /// değişirse (ör. `check()` → `checking` → `optional`) aradaki `checking`
  /// için kaydedilen callback henüz çalışmamışken yeni bir tane daha
  /// kuyruğa girerdi. Bu bayrak aynı frame içinde ikinci kaydı engeller.
  bool _promptScheduled = false;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(updateCheckerProvider.notifier).check());
  }

  /// Durum değiştiğinde ilgili istemi gösterir. Aynı durum için ikinci kez
  /// çalışmaz.
  ///
  /// Not: `identical` yerine `==` karşılaştırması **bilinçli seçildi** —
  /// `UpdateRequired(manifest)`/`UpdateOptional(manifest)` her kontrolde yeni
  /// bir örnek üretir (`check()` her çağrıda yeni manifest okur), bu yüzden
  /// referans eşitliği yalnızca aynı nesne döndüğünde tutar. Aynı durum
  /// için iki farklı örnek gelirse `==` de `false` dönerdi; yalnızca
  /// `_optionalDialogShown`/`_unknownWarningShown` bayrakları koruyor.
  Future<void> _maybeShowPrompts(UpdateStatus status) async {
    if (identical(status, _lastHandledStatus)) return;
    _lastHandledStatus = status;
    // Kilit riski: `UpdateRequired` tek çıkışı olan ekranı gösterir ve
    // `_lastHandledStatus` burada güncellenir. "Yeniden kontrol et" düğmesi
    // `check()`'i tetikler; aynı karar dönerse `identical` tutmaz, ama
    // `UpdateRequired` dalında `default: break` ile **hiçbir istem
    // gösterilmez** — kullanıcı sonsuz uyarı döngüsüne girmez.
    switch (status) {
      case UpdateOptional(:final manifest):
        if (_optionalDialogShown) return;
        // AWAIT SONRASI REF KULLANIMI: `await` sırasında widget dispose
        // olabilir (`mounted` kontrolü aşağıda var) ama `ref.read` çağrısı
        // `await`'tan **önce** başlatıldığı için güvenli.
        final dismissed = await ref
            .read(updateCheckerProvider.notifier)
            .isDismissed(manifest.versionCode);
        if (dismissed) return;
        if (!mounted) return;
        _optionalDialogShown = true;
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
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('updates.optionalTitle'.tr()),
          content: Text('updates.optionalBody'.tr(
            namedArgs: {'version': manifest.versionName},
          )),
          actions: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      ref
                          .read(updateCheckerProvider.notifier)
                          .dismissOptional(manifest.versionCode);
                      Navigator.of(dialogContext).pop();
                    },
              child: Text('updates.later'.tr()),
            ),
            FilledButton(
              // İndirme sürerken buton kilitlenir: `_launchApk` birden çok
              // kez tetiklenip aynı APK'yı paralel indirmek/iki yükleyici
              // açmak yerine tek indirme yapılır.
              onPressed: _busy
                  ? null
                  : () async {
                      setLocal(() => _busy = true);
                      await _launchApk(manifest);
                      if (!dialogContext.mounted) return;
                      setLocal(() => _busy = false);
                    },
              child: Text('updates.updateNow'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  /// APK'yı indirir, `sha256` ile doğrular ve Android yükleyicisine açar.
  ///
  /// Güvenlik zinciri:
  ///  1. `manifest.isApkUrlSafe` — https + `.apk` + `userInfo` yok
  ///     (aksi halde `javascript:`/`intent:`/`file:` dış uygulamaya açılırdı).
  ///  2. `ApkDownloader` indirmeyi uygulama içinde yapar ve `sha256`'ı
  ///     karşılaştırır. **Tutmuyorsa dosya açılmaz** (reddedilir).
  ///  3. Doğrulanmış/geçersiz-geçmez dosya `file://` ile yükleyiciye açılır.
  ///
  /// Zincirin tamamı [downloadVerifyAndOpen] içinde yaşar; burada yalnızca
  /// kullanıcıya gösterilecek metin kararı verilir. `ForceUpdatePage`
  /// (A4 alanı) **aynı** fonksiyonu çağırmalıdır.
  ///
  /// `sha256` manifestte **yoksa** indirme engellenmez — bilinçli karar:
  /// zorunlu güncellemede reddetmek kullanıcıyı geri dönüşsüz kilitler
  /// (bkz. `apk_integrity.dart` başlığındaki gerekçe). Bu durumda
  /// [ApkIntegrityResult.unavailable] döner ve kullanıcıya uyarı gösterilir.
  Future<void> _launchApk(UpdateManifest manifest) async {
    _busy = true;
    try {
      final outcome = await downloadVerifyAndOpen(manifest);
      if (!mounted) return;
      if (outcome.openedWithoutHash) {
        // Hash manifestte yok — kurulum yine de yapılır, kullanıcı bilgilendirilir.
        _notify('updates.unverified'.tr());
      }
      if (outcome.opened) return;
      _notify(
        switch (outcome.status) {
          ApkInstallStatus.integrityFailed => 'updates.integrityFailed'.tr(),
          ApkInstallStatus.tooLarge => 'updates.tooLarge'.tr(),
          _ => 'updates.downloadFailed'.tr(),
        },
      );
    } finally {
      if (mounted) _busy = false;
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(updateCheckerProvider);
    // Durum değiştiğinde yalnızca bir kez post-frame kaydedilir. Önceki
    // sürüm her frame'de `addPostFrameCallback` çağırıyordu; widget
    // arka plana alınınca (veya hızlı yeniden çizimlerde) kuyruk büyüyor,
    // toplanan callback'ler uygulama açıldığında SnackBar/dialog göstermeye
    // çalışıyordu.
    if (!identical(status, _lastHandledStatus) && !_promptScheduled) {
      _promptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _promptScheduled = false;
        unawaited(_maybeShowPrompts(status));
      });
    }

    return switch (status) {
      UpdateRequired(:final manifest) => ForceUpdatePage(manifest: manifest),
      _ => widget.child,
    };
  }
}
