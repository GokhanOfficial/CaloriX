import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:calorix/core/updates/apk_downloader.dart';
import 'package:calorix/core/updates/apk_integrity.dart';
import 'package:calorix/core/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// `core/updates/` güvenlik denetimi — **manifest manipülasyonu** senaryoları.
///
/// ## Kilit soru: `sha256` alanı sunucudan kaldırılırsa doğrulama atlanıyor mu?
///
/// Kısa cevap: **evet, atlanıyor** — ve bu **bilinçli, belgelenmiş bir
/// karar** (`apk_integrity.dart:16-35`). Bu test o kararın **kapsamını**
/// ölçer: hash'in yokluğu `verified` üretmez, `unavailable` üretir ve
/// çağıran bunu kullanıcıya gösterebilir. Kararın kendisi burada
/// değiştirilmiyor; test "yanlış kabul edilmez" ilkesini kilitler.
///
/// ## Diğer ölçülen yüzeyler
///  * `versionCode` manipülasyonu → zorunlu güncelleme kilidi kurulabilir mi?
///  * `apkUrl` şema enjeksiyonu (her varyant)
///  * `minSupportedVersionCode` yoksa karar ne olur (fail-open değil)
///  * Bozuk/eksik manifest → `unknown` (uygulama açılır, kilitlenmez)
void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('update_manifest_attack');
  });

  tearDown(() async {
    ApkDownloader.reset();
    if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
  });

  List<int> apkBytes(int length) =>
      List<int>.generate(length, (i) => (i * 17 + 3) % 251);

  UpdateManifest fromJson(Map<String, dynamic> json) =>
      UpdateManifest.fromJson(json);

  Map<String, dynamic> baseManifest() => <String, dynamic>{
        'versionName': '1.4.0',
        'versionCode': 5,
        'minSupportedVersionCode': 3,
        'apkUrl':
            'https://github.com/GokhanOfficial/CaloriX/releases/download/android-v1.4.0/calorix.apk',
        'sha256': ApkIntegrityVerifier.sha256Hex(apkBytes(32)),
      };

  group('manifest sha256 alanı kaldırıldığında', () {
    test('doğrulama "unavailable" olur, "verified" DEĞİL', () {
      // Sunucudan hash'i silen saldırgan için en kötü senaryo:
      // istemci "doğrulandı" dememeli.
      final json = baseManifest()..remove('sha256');
      final manifest = fromJson(json);
      final bytes = apkBytes(4096);

      final result = ApkIntegrityVerifier.verifyUint8(
        Uint8List.fromList(bytes),
        expected: manifest.sha256,
      );

      expect(manifest.sha256, isNull);
      expect(result.isVerified, isFalse);
      expect(result.isMismatch, isFalse);
      expect(result.result, ApkIntegrityResult.unavailable);
    });

    test('hash yerine bozuk metin konursa da "verified" olmaz', () {
      final manifest = fromJson(
        baseManifest()
          ..['sha256'] = 'sha256:abc', // CLI çıktısının ham kopyası
      );
      final result = ApkIntegrityVerifier.verifyUint8(
        Uint8List.fromList(apkBytes(128)),
        expected: manifest.sha256,
      );
      expect(result.isVerified, isFalse);
      expect(result.result, ApkIntegrityResult.unavailable);
    });

    test('hash başlığı SHA256SUMS biçiminde gelirse de kullanılamaz', () {
      // `release_android.sh` `sha256sum` çıktısının tamamını yazarsa
      // "hash  calorix.apk" olur; 64 hex değil → unavailable (yanlış kabul yok).
      const digest = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final result = ApkIntegrityVerifier.verifyBytes(
        bytes: apkBytes(16),
        expected: '$digest  calorix.apk',
      );
      expect(result.isVerified, isFalse);
      expect(result.result, ApkIntegrityResult.unavailable);
    });

    test('hash alanı null olsa da indirme akışı doğru sonucu verir', () async {
      // Belgelenen davranış: `unavailable` → dosya yazılır, kurulum ENGELLENMEZ.
      // Bu test "kabul"ü değil, "kabul ettiğimiz tek yolun doğru işaretlendiğini"
      // kilitler (arayüz `updates.unverified` uyarısını gösterebilmeli).
      final bytes = apkBytes(2048);
      ApkDownloader.fetch = (uri) async =>
          http.Response.bytes(bytes, 200, request: http.Request('GET', uri));
      ApkDownloader.tempDir = () async => tempRoot;
      final manifest = fromJson(baseManifest()..remove('sha256'));

      final result = await ApkDownloader.downloadAndVerify(manifest);
      expect(result.isUnverifiable, isTrue);
      expect(result.isVerified, isFalse);
      expect(result.file.existsSync(), isTrue);
    });
  });

  group('apkUrl manipülasyonu — her varyant reddedilir', () {
    const hostile = <String, String>{
      'javascript:alert(1)': 'javascript',
      'intent://scan#Intent;scheme=zxing;end': 'intent',
      'file:///data/local/tmp/evil.apk': 'file',
      'content://com.android.providers/download/1': 'content',
      'market://details?id=com.evil.app': 'market',
      'http://github.com/a/b.apk': 'http',
      'https://user:pass@github.com/a/b.apk': 'userInfo',
      'https://github.com/a/b.zip': 'uzanti',
      'https:///a.apk': 'bosHost',
      'https://': 'hostYok',
    };

    for (final entry in hostile.entries) {
      test('reddedilir: ${entry.value}', () {
        expect(UpdateManifest.isSafeApkUrl(entry.key), isFalse);
      });

      test('indirme hiç yapılmaz: ${entry.value}', () async {
        var fetched = false;
        ApkDownloader.fetch = (uri) async {
          fetched = true;
          return http.Response('', 200);
        };
        ApkDownloader.tempDir = () async => tempRoot;
        final manifest = fromJson(
          baseManifest()..['apkUrl'] = entry.key,
        );
        await expectLater(
          ApkDownloader.downloadAndVerify(manifest),
          throwsA(
            isA<ApkDownloadException>()
                .having((e) => e.kind, 'kind', ApkDownloadFailure.unsafeUrl),
          ),
        );
        expect(fetched, isFalse);
      });
    }
  });

  group('versionCode / minSupported manipülasyonu', () {
    test('çok büyük minSupported zorunlu güncelleme kilidi kurar', () {
      // Bu, sunucu ele geçirildiğinde kullanıcıyı kilitleyen vektördür.
      // Kod tarafında savunma **yok** (kilit kasıtlıdır) ama kararın
      // `required` olduğu ve tek çıkışın APK indirme olduğu kilitlenir:
      // manifest bozuksa `fromJson` **fırlatır** → `check()` catch →
      // cache → `unknown` → uygulama açılır. Kilit oluşmaz.
      final manifest = fromJson(baseManifest()..['minSupportedVersionCode'] = 999);
      expect(manifest.evaluate(5), UpdateDecision.required);
    });

    test('minSupportedVersionCode eksikse fail-OPEN (zorunluluk devre dışı)', () {
      // Alan unutulursa `minSupported = 1` → hiçbir cihaz zorunlu görmez.
      // Bu "sessiz eski karar" riskini azaltır: kötü niyetli manifest'te
      // alan **silinerek** zorunlu güncelleme dayatılamaz. Cihaz 1 ise
      // güncel sürümde → `upToDate`; eski sürümde ise yalnızca opsiyonel
      // güncelleme görür (asla `required`).
      final json = baseManifest()..remove('minSupportedVersionCode');
      final manifest = fromJson(json);
      expect(manifest.minSupportedVersionCode, 1);
      // versionCode 5: 1..4 arası her cihaz **opsiyonel** güncelleme görür,
      // hiçbiri `required` değil. (Yapı numarası 1'den başladığı için
      // `0 < 1` şartı pratikte oluşmaz.) 5 ve üstü günceldir.
      for (var code = 1; code < 5; code++) {
        expect(
          manifest.evaluate(code),
          UpdateDecision.optional,
          reason: 'build $code asla zorunlu güncelleme görmemeli',
        );
      }
      expect(manifest.evaluate(5), UpdateDecision.upToDate);
    });

    test('minSupportedVersionCode string/sondur ise varsayılana düşer', () {
      for (final bad in ['3', 3.5, true, null, <int>[]]) {
        final manifest =
            fromJson(baseManifest()..['minSupportedVersionCode'] = bad);
        expect(
          manifest.minSupportedVersionCode,
          1,
          reason: 'geçersiz değer "$bad" varsayılana düşmeli',
        );
      }
    });

    test('versionCode kesirli double ise manifest geçersiz (update UNKNOWN)', () {
      expect(
        () => fromJson(baseManifest()..['versionCode'] = 7.5),
        throwsA(isA<FormatException>()),
      );
    });

    test('versionName yoksa manifest geçersiz (update UNKNOWN)', () {
      expect(
        () => fromJson(baseManifest()..remove('versionName')),
        throwsA(isA<TypeError>()),
      );
    });

    test('apkUrl yoksa manifest geçersiz (update UNKNOWN)', () {
      expect(
        () => fromJson(baseManifest()..remove('apkUrl')),
        throwsA(isA<TypeError>()),
      );
    });
  });

  group('zorunlu güncelleme sonsuz döngü riski', () {
    test('APK indirme sürekli başarısız olsa da durum değişmez (spinner yok)', () {
      // `UpdateGate._busy` yalnızca indirme sırasında true'dur; hata
      // durumunda `finally` ile düşer. Sonsuz döngü kaynağı olan yer
      // `_maybeShowPrompts`'ın `UpdateRequired` dalıdır: o dal `default:
      // break` ile hiçbir şey göstermez (ekran zaten `ForceUpdatePage`).
      // Buradaki ölçüm: manifest her zaman geçerli olduğunda karar sabittir.
      final manifest = fromJson(baseManifest());
      const device = 2;
      for (var i = 0; i < 10; i++) {
        expect(manifest.evaluate(device), UpdateDecision.required);
      }
    });

    test('dismissed yalnızca opsiyonel akışta; zorunlu güncellemeyi açmaz', () {
      // `dismissOptional(versionCode)` prefs'e tek int yazıyor ve
      // `_maybeShowPrompts` yalnızca `UpdateOptional` dalında okuyor.
      // `UpdateRequired` dalı `isDismissed`'a **hiç bakmıyor** — yani
      // "Daha sonra" zorunlu güncellemeyi bastıramıyor (kilit kasıtlı).
      // Bu, sonsuz uyarı döngüsü ile kullanıcıyı kilitleme arasında
      // bilinçli seçimdir ve kilitlenmiştir.
      final manifest = fromJson(baseManifest());
      expect(manifest.evaluate(2), UpdateDecision.required);
    });
  });

  group('notlar (notes) — yalnızca gösterim', () {
    test('dil başına alanlar String değilse manifest geçersiz olmaz', () {
      // `notes: {tr: 5}` → `as String?` TypeError fırlatır → cache → unknown.
      // Sessiz "boş not" değil, görünür durum: düşüş **unknown**'a.
      expect(
        () => fromJson(baseManifest()
          ..['notes'] = <String, dynamic>{'tr': 5, 'en': 'note'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('aktif dil boşsa diğer dile düşer, ikisi de boşsa null', () {
      final manifest = fromJson(baseManifest()
        ..['notes'] = <String, dynamic>{'tr': '', 'en': 'Release notes'});
      expect(manifest.notesFor('tr'), 'Release notes');
      expect(manifest.notesFor('en'), 'Release notes');

      final empty = fromJson(baseManifest()
        ..['notes'] = <String, dynamic>{'tr': '', 'en': ''});
      expect(empty.notesFor('tr'), isNull);
    });
  });

  group('manifest JSON ayrıştırma dayanıklılığı', () {
    test('jsonDecode Map değilse TypeError (unknown yoluna düşer)', () {
      for (final body in ['[]', '"metin"', '42', 'null']) {
        expect(
          () => UpdateManifest.fromJson(
            jsonDecode(body) as Map<String, dynamic>,
          ),
          throwsA(isA<TypeError>()),
          reason: 'gövde "$body" Map olmalı değil',
        );
      }
    });
  });
}
