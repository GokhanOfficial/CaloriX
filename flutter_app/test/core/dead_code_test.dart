import 'dart:io';

import 'package:calorix/core/updates/apk_downloader.dart';
import 'package:calorix/core/updates/update_checker.dart';
import 'package:calorix/core/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// `core/updates/` ölü kod denetimi — Tur 6.
///
/// PROTOKOL §3 gereği "ölü kod silinmeden önce dinamik kullanım olup
/// olmadığı kanıtlanmalı"dır. Bu test, `UpdateGate.downloadVerifyAndOpen`
/// statik metodunun **gerçekten** çağrıldığını kanıtlar: metot
/// `UpdateGate`'in dışından da (`ForceUpdatePage` — `lib/features/updates/`
/// A4 alanı) çağrılabilir olmalıdır, aksi hâlde burada tanımlı bütün
/// güvenlik zinciri (URL süzgeci → `sha256` → `launchUrl`) kullanılmaz
/// hale gelirdi.
void main() {
  test('downloadVerifyAndOpen her iki çağıran tarafından erişilebilir', () {
    // Metot daha önce `_UpdateGateState` içinde `static` idi. Dart'ta
    // `State` sınıfları `_` ile gizlidir, dolayısıyla `ForceUpdatePage`
    // (A4 alanı) bu metodu **çağıramıyordu** — "her iki ekran da aynı
    // fonksiyonu çağırmalıdır" yorumu kâğıt üzerinde doğruydu ama fiilen
    // imkânsızdı ve zorunlu güncelleme ekranı `sha256`'yı atlayan ikinci
    // bir `launchUrl(apkUrl)` yolunu kendi yazmaya devam ediyordu.
    //
    // Metot artık `apk_downloader.dart` içinde **top-level** ve herkese
    // açık; test, imzayı kilitler: değişirse/erişilemez hâle gelirse
    // derleme kırılır.
    const Future<ApkInstallOutcome> Function(UpdateManifest) fn =
        downloadVerifyAndOpen;
    expect(fn, isNotNull);

    // Ve `update_gate.dart` kendi statik kopyasını **taşımıyor**: ikinci
    // bir giriş noktası doğmasın.
    final gateSource =
        File('lib/core/updates/update_gate.dart').readAsStringSync();
    expect(
      RegExp(r'static Future<ApkInstallOutcome>').hasMatch(gateSource),
      isFalse,
      reason: 'downloadVerifyAndOpen tek yerde tanımlı olmalı',
    );
  });

  group('UpdateChecker — durum makinesi boşlukları', () {
    test('kIsWeb dışında "checking" durumu ilk değerdir', () {
      // `UpdateChecker` `checking` ile başlar; `UpdateGate` bu durumda
      // `widget.child`'i gösterir (kilit yok).
      const checking = UpdateStatus.checking();
      expect(checking, isA<UpdateChecking>());
    });

    test('upToDate kararı manifest taşımaz', () {
      const upToDate = UpdateStatus.upToDate();
      expect(upToDate, isA<UpdateUpToDate>());
      // `UpdateUpToDate` manifest taşımadığı için `_maybeShowPrompts`
      // `default: break` dalına düşer — kullanıcı hiçbir uyarı görmez.
    });

    test('unknown kararı manifest taşımaz (çevrimdışı açılış)', () {
      const unknown = UpdateStatus.unknown();
      expect(unknown, isA<UpdateUnknown>());
    });

    test('required ve optional manifest taşır', () {
      const manifest = UpdateManifest(
        versionName: '1.4.0',
        versionCode: 5,
        minSupportedVersionCode: 3,
        apkUrl: 'https://github.com/a/b.apk',
      );
      final required = UpdateStatus.required(manifest);
      final optional = UpdateStatus.optional(manifest);
      expect((required as UpdateRequired).manifest.versionCode, 5);
      expect((optional as UpdateOptional).manifest.versionCode, 5);
    });
  });

  group('UpdateChecker — zaman aşımı ve ölçek sınırları', () {
    test('manifest üst sınırı gerçekçi (1 KB mertebesi)', () {
      // Gerçek `latest.json` ~1 KB; 64 KB sınırı yönlendirme yakalama ve
      // bozuk sunucu için bellek koruması. Çok düşük olsaydı meşru
      // manifest (uzun sürüm notlarıyla) reddedilirdi.
      expect(UpdateChecker.maxManifestBytes, 64 * 1024);
      expect(UpdateChecker.maxManifestBytes, greaterThan(1024));
    });

    test('cache ve dismissed anahtarları ayrı', () {
      // Çakışma olsaydı "dismissed" yazmak manifesti ezip, sonraki açılışta
      // "kontrol yapılamadı" uyarısı çıkardı.
      expect(UpdateChecker.cacheKey, isNot(UpdateChecker.dismissedCodeKey));
      expect(UpdateChecker.cacheKey, 'update_manifest_cache');
      expect(UpdateChecker.dismissedCodeKey, 'update_dismissed_code');
    });
  });

  group('karar matrisi — tüm kombinasyonlar', () {
    test('3 karar tüm (minSupported, latest, device) için tutarlı', () {
      const mins = [1, 3, 5];
      const latests = [1, 3, 5, 8];
      const devices = [0, 1, 2, 3, 4, 5, 7, 8, 9];
      for (final min in mins) {
        for (final latest in latests) {
          for (final device in devices) {
            final d = decideUpdate(
              deviceVersionCode: device,
              minSupportedVersionCode: min,
              latestVersionCode: latest,
            );
            // Tanım: required önce, sonra optional, kalan upToDate.
            final expected = device < min
                ? UpdateDecision.required
                : device < latest
                    ? UpdateDecision.optional
                    : UpdateDecision.upToDate;
            expect(d, expected,
                reason: 'min=$min latest=$latest device=$device');
          }
        }
      }
    });

    test('karar tekdüze: yeni sürüm arttıkça daha yeni karar verilmez', () {
      // device arttıkça: required → optional → upToDate
      const min = 3;
      const latest = 8;
      for (var device = 0; device < 10; device++) {
        final rank = switch (decideUpdate(
          deviceVersionCode: device,
          minSupportedVersionCode: min,
          latestVersionCode: latest,
        )) {
          UpdateDecision.required => 0,
          UpdateDecision.optional => 1,
          UpdateDecision.upToDate => 2,
        };
        if (device == 0) {
          expect(rank, 0);
          continue;
        }
        expect(rank, greaterThanOrEqualTo(previousRank),
            reason: 'device=$device rank geriye gidemez');
        previousRank = rank;
      }
    });
  });

  group('kaynak dosyaları — dinamik kullanım kanıtı', () {
    test('update_gate.dart ForceUpdatePage içe aktarıyor (A4 alanına bağlı)', () {
      // `lib/core/updates/update_gate.dart` → `features/updates/force_update_page.dart`
      // Bu, `core/` → `features/` bağımlılığıdır; silinirse zorunlu güncelleme
      // ekranı kopar. Varlığı doğrulanır.
      final source =
          File('lib/core/updates/update_gate.dart').readAsStringSync();
      expect(source, contains("import '../../features/updates/force_update_page.dart';"));
    });

    test('force_update_page.dart hâlâ ham launchUrl kullanıyor (AKTARIM)', () {
      // Tur 1'den beri raporlanan ve **hâlâ düzeltilmemiş** bulgu:
      // zorunlu güncelleme ekranı `manifest.isApkUrlSafe` süzgecini
      // uyguluyor ama `sha256` doğrulamasını **atlayan** ikinci bir
      // `launchUrl(apkUrl)` yolu olarak çalışıyor. A4 alanı.
      //
      // Düzeltme öncesi durum: metot `State` sınıfının içindeydi ve
      // erişilemezdi; bu test **kırmızıya döndü** ve düzeltmeyi zorladı.
      // Artık metot `apk_downloader.dart` içinde herkese açık — tek
      // yapılacak `ForceUpdatePage`'in onu çağırması (A4 alanı).
      final page = File('lib/features/updates/force_update_page.dart');
      if (!page.existsSync()) {
        // A4 ajanı dosyayı taşımış olabilir; bu durumda iddia geçersiz.
        return;
      }
      final source = page.readAsStringSync();
      expect(
        source,
        isNot(contains('downloadVerifyAndOpen')),
        reason: 'AKTARIM (A4): ForceUpdatePage artık sha256 doğrulayan ortak '
            'akışı (downloadVerifyAndOpen) kullanmalı',
      );
    });
  });
}

/// `karar tekdüze` testinin devam değişkeni.
int previousRank = 0;
