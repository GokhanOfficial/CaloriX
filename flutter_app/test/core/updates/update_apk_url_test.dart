import 'package:calorix/core/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// `apkUrl` doğrulama süzgeci — manifest uzak sunucudan gelir ve adres
/// doğrudan `url_launcher`'a verilir. Şema/uzantı kontrolü olmadan
/// `javascript:`, `intent:`, `file:` şemaları açılabilir.
void main() {
  UpdateManifest manifestWith(String url) => UpdateManifest.fromJson({
        'versionName': '1.3.0',
        'versionCode': 4,
        'apkUrl': url,
      });

  group('isSafeApkUrl — kabul edilenler', () {
    test('tool/release_android.sh ürettiği meşru GitHub APK adresi', () {
      const url = 'https://github.com/GokhanOfficial/CaloriX/releases/download/'
          'android-v1.3.0%2B4/calorix.apk';
      expect(UpdateManifest.isSafeApkUrl(url), isTrue);
      expect(manifestWith(url).isApkUrlSafe, isTrue);
    });

    test('büyük harfli .APK uzantısı kabul edilir', () {
      expect(
        UpdateManifest.isSafeApkUrl('https://example.com/calorix.APK'),
        isTrue,
      );
    });

    test('baştaki/ sondaki boşluk temizlenir', () {
      expect(
        UpdateManifest.isSafeApkUrl('  https://example.com/a.apk  '),
        isTrue,
      );
    });
  });

  group('isSafeApkUrl — reddedilenler', () {
    test('http (düz metin) reddedilir', () {
      expect(UpdateManifest.isSafeApkUrl('http://example.com/a.apk'), isFalse);
    });

    test('javascript: şeması reddedilir', () {
      expect(
        UpdateManifest.isSafeApkUrl('javascript:alert(document.cookie)'),
        isFalse,
      );
    });

    test('intent: şeması reddedilir', () {
      expect(
        UpdateManifest.isSafeApkUrl(
          'intent://scan/#Intent;scheme=zxing;end',
        ),
        isFalse,
      );
    });

    test('file: şeması yerel dosya okuma riski nedeniyle reddedilir', () {
      expect(
        UpdateManifest.isSafeApkUrl('file:///data/data/com.calorix/shared_prefs/x.xml'),
        isFalse,
      );
    });

    test('market:// yönlendirmesi reddedilir', () {
      expect(
        UpdateManifest.isSafeApkUrl('market://details?id=com.evil.app'),
        isFalse,
      );
    });

    test('.apk uzantısı olmayan https adresi reddedilir', () {
      expect(UpdateManifest.isSafeApkUrl('https://example.com/'), isFalse);
      expect(
        UpdateManifest.isSafeApkUrl('https://example.com/redirect?to=evil'),
        isFalse,
      );
    });

    test('gömülü kimlik bilgisi (https://user:pass@host) reddedilir', () {
      expect(
        UpdateManifest.isSafeApkUrl('https://user:pass@example.com/a.apk'),
        isFalse,
      );
    });

    test('host boş reddedilir', () {
      expect(UpdateManifest.isSafeApkUrl('https:///a.apk'), isFalse);
    });

    test('parse edilemeyen girdi istisna atmaz, false döner', () {
      expect(UpdateManifest.isSafeApkUrl('::::'), isFalse);
      expect(UpdateManifest.isSafeApkUrl('   '), isFalse);
    });
  });

  group('sürüm notu fallback zinciri', () {
    test('boş string not "yok" sayılır, diğer dile düşer', () {
      // A3r2 düzeltmesi: `'' ?? y` → boş string döndürüyordu ve UI'da
      // "Bu sürümde" başlıklı boş kart gösteriliyordu. Boş string artık
      // "yok" muamelesi görür, `en` notuna düşer.
      final m = UpdateManifest.fromJson(const {
        'versionName': '1.0.0',
        'versionCode': 1,
        'apkUrl': 'https://example.com/a.apk',
        'notes': {'tr': '', 'en': 'en notu'},
      });
      expect(m.notesTr, '');
      expect(m.notesFor('tr'), 'en notu');
    });

    test('iki dil de boşsa null döner (boş kart gösterilmez)', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '1.0.0',
        'versionCode': 1,
        'apkUrl': 'https://example.com/a.apk',
        'notes': {'tr': '', 'en': ''},
      });
      expect(m.notesFor('tr'), isNull);
      expect(m.notesFor('en'), isNull);
    });
  });
}
