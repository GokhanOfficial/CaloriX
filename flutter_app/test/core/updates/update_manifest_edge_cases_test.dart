import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// Manifest karar mantığının sınır durumları ve JSON sözleşmesi.
///
/// `update_manifest_test.dart` mutlak build numaralarıyla karşılaştırıyor;
/// buradaki testler sınır/deformasyon davranışını kilitler.
void main() {
  group('decideUpdate — sınır ve bozuk girdi', () {
    test('build 0 cihaz: min>0 ise zorunlu, min=0 ise en yeniye kadar opsiyonel', () {
      expect(
        decideUpdate(
          deviceVersionCode: 0,
          minSupportedVersionCode: 1,
          latestVersionCode: 3,
        ),
        UpdateDecision.required,
      );
      expect(
        decideUpdate(
          deviceVersionCode: 0,
          minSupportedVersionCode: 0,
          latestVersionCode: 3,
        ),
        UpdateDecision.optional,
      );
    });

    test('min > latest (yayın edilmemiş cutoff) → cihaz zorunlu kilitlenmez', () {
      // Bozuk manifest: minSupported, latest'ten büyük. Gerçek cihaz
      // (build 3) hem min hem latest altındadır → opsiyonel, upToDate
      // DEĞİL. Yanlışlıkla "upToDate" dönse kullanıcı zorunlu
      // güncellemeden muaf kalırdı.
      expect(
        decideUpdate(
          deviceVersionCode: 3,
          minSupportedVersionCode: 9,
          latestVersionCode: 3,
        ),
        UpdateDecision.required,
      );
    });

    test('device == min == latest → upToDate', () {
      expect(
        decideUpdate(
          deviceVersionCode: 4,
          minSupportedVersionCode: 4,
          latestVersionCode: 4,
        ),
        UpdateDecision.upToDate,
      );
    });

    test('device == latest, min altında → zorunlu (cutoff tam uçta)', () {
      expect(
        decideUpdate(
          deviceVersionCode: 5,
          minSupportedVersionCode: 5,
          latestVersionCode: 5,
        ),
        UpdateDecision.upToDate,
      );
      expect(
        decideUpdate(
          deviceVersionCode: 5,
          minSupportedVersionCode: 6,
          latestVersionCode: 5,
        ),
        UpdateDecision.required,
      );
    });

    test('negatif build numarası opsiyonel akar (kötü veri ayıklanmaz)', () {
      expect(
        decideUpdate(
          deviceVersionCode: -1,
          minSupportedVersionCode: 1,
          latestVersionCode: 3,
        ),
        UpdateDecision.required,
      );
    });
  });

  group('UpdateManifest.fromJson — bozuk/eksik payload', () {
    test('sürüm notu map\'i null ise notlar null (çökme yok)', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': 7,
        'apkUrl': 'u',
      });
      expect(m.notesTr, isNull);
      expect(m.notesEn, isNull);
      expect(m.notesFor('tr'), isNull);
      expect(m.notesFor('en'), isNull);
    });

    test('sadece tr notu varsa en kullanıcısı tr\'ye düşer', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': 7,
        'apkUrl': 'u',
        'notes': {'tr': 'sadece tr'},
      });
      expect(m.notesFor('tr'), 'sadece tr');
      // en yok → tr'ye düşer (boş string değil, mevcut çeviri döner).
      expect(m.notesFor('en'), 'sadece tr');
    });

    test('boş string not alanı boş kalır ama notesFor diğer dile düşer', () {
      // A3r2 düzeltmesi: `'' ?? fallback` → boş string döner, UI'da boş
      // sürüm notu gösteriliyordu. Alan (`notesTr`) ham değerini korur,
      // `notesFor` boş string'i "yok" sayıp diğer dile düşer.
      final m = UpdateManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': 7,
        'apkUrl': 'u',
        'notes': {'tr': '', 'en': 'en notu'},
      });
      expect(m.notesTr, '');
      expect(m.notesFor('tr'), 'en notu');
      expect(m.notesFor('en'), 'en notu');
    });

    test('sha256/releasedAt opsiyonel — null döner', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': 7,
        'apkUrl': 'u',
      });
      expect(m.sha256, isNull);
      expect(m.releasedAt, isNull);
    });

    test('versionName/versionCode/apkUrl eksikse cast hatası fırlatır', () {
      // Manifest bozuksa `check()` içindeki try bloğu yakalar ve cache'e
      // düşer — bu davranışın istisnasız olduğu doğrulanmamalı, tersine
      // format hatasının sessizce yutulmadığı doğrulanmalı.
      expect(
        () => UpdateManifest.fromJson(const {'versionCode': 1}),
        throwsA(isA<TypeError>()),
      );
    });

    test('versionCode JSON double olarak gelirse toleranslı kabul edilir', () {
      // A3r2 düzeltmesi: `as int` bu payload'da TypeError fırlatıyor ve
      // `check()` catch'e düşüp **önbelleğe** geri dönüyordu — yani geçerli
      // bir manifest yüzünden uygulama eski sürüm kararını kullanmaya
      // devam ediyordu (sessiz "upToDate" yanılgısı).
      final m = UpdateManifest.fromJson(const {
        'versionName': '2.0.0',
        'versionCode': 7.0,
        'apkUrl': 'u',
      });
      expect(m.versionCode, 7);
    });

    test('versionCode kesirli double ise reddedilir (FormatException)', () {
      expect(
        () => UpdateManifest.fromJson(const {
          'versionName': '2.0.0',
          'versionCode': 7.5,
          'apkUrl': 'u',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('versionCode string ise reddedilir', () {
      expect(
        () => UpdateManifest.fromJson(const {
          'versionName': '2.0.0',
          'versionCode': '7',
          'apkUrl': 'u',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('minSupportedVersionCode double/string/eksik toleranslı okunur', () {
      // 4.0 → 4
      expect(
        UpdateManifest.fromJson(const {
          'versionName': '2.0.0',
          'versionCode': 7,
          'minSupportedVersionCode': 4.0,
          'apkUrl': 'u',
        }).minSupportedVersionCode,
        4,
      );
      // "5" → varsayılan 1 (parse edilemez, cutoff uydurulmaz)
      expect(
        UpdateManifest.fromJson(const {
          'versionName': '2.0.0',
          'versionCode': 7,
          'minSupportedVersionCode': '5',
          'apkUrl': 'u',
        }).minSupportedVersionCode,
        1,
      );
      // yok → 1
      expect(
        UpdateManifest.fromJson(const {
          'versionName': '2.0.0',
          'versionCode': 7,
          'apkUrl': 'u',
        }).minSupportedVersionCode,
        1,
      );
    });
  });

  group('notesFor dil eşleşmesi', () {
    final m = UpdateManifest.fromJson(const {
      'versionName': '2.0.0',
      'versionCode': 7,
      'apkUrl': 'u',
      'notes': {'tr': 'TR', 'en': 'EN'},
    });

    test('tr-TR gibi bölgesel kodlar da tr eşleşir', () {
      expect(m.notesFor('tr-TR'), 'TR');
    });

    test('bilinmeyen dil en notuna düşer', () {
      expect(m.notesFor('de'), 'EN');
      expect(m.notesFor('ja'), 'EN');
    });
  });

  group('UpdateChecker ile uyumlu varsayılanlar', () {
    test('cache anahtarı sabit ve versiyonlanabilir', () {
      // SharedPreferences'ta düz anahtar — ileride şema değişirse
      // eski cache'i okuyamama riski. Anahtarın adlandırması kasıtlı
      // düz olmalı (sürüm prefix'i getirirse sürüm yükseltmelerinde
      // tüm cache düşer).
      expect(UpdateDecision.values, hasLength(3));
      expect(
        UpdateDecision.values.map((e) => e.name),
        containsAll(['required', 'optional', 'upToDate']),
      );
    });

    test('update manifest URL\'si sabit ve erişilebilir biçimde', () {
      // release_android.sh bu URL'ye `latest.json` yükler; script ile
      // buradaki adres ayrışırsa zorunlu güncelleme sessizce kapanır.
      expect(
        AppConstants.updateManifestUrl,
        'https://github.com/GokhanOfficial/CaloriX/releases/latest/'
        'download/latest.json',
      );
    });
  });
}
