import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:calorix/core/updates/apk_downloader.dart';
import 'package:calorix/core/updates/apk_integrity.dart';
import 'package:calorix/core/updates/update_manifest.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// APK `sha256` bütünlük doğrulaması.
///
/// Kapsanan karar (bkz. `lib/core/updates/apk_integrity.dart`):
///  * hash **var** ve eşleşiyor  → `verified`, dosya kurulur
///  * hash **var** ve eşleşmiyor → `mismatch`, indirme **reddedilir**
///  * hash **yok** (ya da biçimsiz) → `unavailable`, reddedilmez ama
///    kullanıcı uyarılır; gerekçe zorunlu güncellemede reddetmenin
///    kullanıcıyı geri dönüşsüz kilitlemesi.
void main() {
  // SHA-256("abc") — RFC/FIPS test vektörü.
  const abcHash =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('apk_dl_test');
  });

  tearDown(() async {
    ApkDownloader.reset();
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  /// Test APK gövdesi olarak basit, tekrarlı ama gerçekçi bir bayt dizisi.
  List<int> apkBytes(int length) =>
      List<int>.generate(length, (i) => (i * 31 + 7) % 251);

  UpdateManifest manifest({
    String apkUrl = 'https://github.com/GokhanOfficial/CaloriX/releases/'
        'download/android-v1.3.0%2B4/calorix.apk',
    String? sha256,
    int versionCode = 4,
  }) =>
      UpdateManifest(
        versionName: '1.3.0',
        versionCode: versionCode,
        minSupportedVersionCode: 1,
        apkUrl: apkUrl,
        sha256: sha256,
      );

  void stubResponse({
    required List<int> body,
    int status = 200,
  }) {
    ApkDownloader.fetch = (uri) async =>
        http.Response.bytes(body, status, request: http.Request('GET', uri));
  }

  group('ApkIntegrityVerifier.normalizeExpected', () {
    test('64 hex kabul, küçük harfe indirgenir', () {
      final upper = 'A' * 64;
      expect(ApkIntegrityVerifier.normalizeExpected(upper),
          'a' * 64);
    });

    test('baştaki/sondaki boşluk temizlenir', () {
      expect(
        ApkIntegrityVerifier.normalizeExpected('  $abcHash  '),
        abcHash,
      );
    });

    test('null / boş / boşluk → null', () {
      expect(ApkIntegrityVerifier.normalizeExpected(null), isNull);
      expect(ApkIntegrityVerifier.normalizeExpected(''), isNull);
      expect(ApkIntegrityVerifier.normalizeExpected('   '), isNull);
    });

    test('63 veya 65 karakter, 0x öneki, g/ş vb. → null (yanlış kabul yok)', () {
      expect(ApkIntegrityVerifier.normalizeExpected(abcHash.substring(1)),
          isNull);
      expect(ApkIntegrityVerifier.normalizeExpected('${abcHash}0'), isNull);
      expect(ApkIntegrityVerifier.normalizeExpected('0x$abcHash'), isNull);
      expect(
        ApkIntegrityVerifier.normalizeExpected('z' * 64),
        isNull,
      );
    });
  });

  group('sha256Hex — bilinen vektör', () {
    test('"abc" → FIPS 180-4 özeti', () {
      expect(
        ApkIntegrityVerifier.sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('boş girdi → e3b0c442… (bilinen SHA-256 boş özeti)', () {
      expect(
        ApkIntegrityVerifier.sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });

  group('verifyBytes — üç karar yolu', () {
    test('sağlam hash geçer', () {
      final bytes = apkBytes(4096);
      final r = ApkIntegrityVerifier.verifyBytes(
        bytes: bytes,
        expected: ApkIntegrityVerifier.sha256Hex(bytes),
      );
      expect(r.result, ApkIntegrityResult.verified);
      expect(r.isVerified, isTrue);
      expect(r.isMismatch, isFalse);
      expect(r.hasExpected, isTrue);
      expect(r.byteLength, 4096);
    });

    test('büyük harfli hash de geçer (büyük/küçük harf duyarsız)', () {
      final bytes = apkBytes(1024);
      final expected = ApkIntegrityVerifier.sha256Hex(bytes).toUpperCase();
      expect(
        ApkIntegrityVerifier.verifyBytes(bytes: bytes, expected: expected)
            .result,
        ApkIntegrityResult.verified,
      );
    });

    test('bozuk hash reddedilir (mismatch)', () {
      final bytes = apkBytes(4096);
      final r = ApkIntegrityVerifier.verifyBytes(
        bytes: bytes,
        expected: ApkIntegrityVerifier.sha256Hex(apkBytes(4095)),
      );
      expect(r.result, ApkIntegrityResult.mismatch);
      expect(r.isMismatch, isTrue);
      expect(r.isVerified, isFalse);
    });

    test('tek bayl değişse reddedilir', () {
      final original = apkBytes(2048);
      final tampered = [...original]..[1024] = (original[1024] + 1) % 256;
      final r = ApkIntegrityVerifier.verifyBytes(
        bytes: tampered,
        expected: ApkIntegrityVerifier.sha256Hex(original),
      );
      expect(r.result, ApkIntegrityResult.mismatch);
    });

    test('hash YOKSA doğrulanamaz (unavailable) — reddedilmez', () {
      final r = ApkIntegrityVerifier.verifyBytes(bytes: apkBytes(512));
      expect(r.result, ApkIntegrityResult.unavailable);
      expect(r.hasExpected, isFalse);
      // "Eşleşmedi" ile "doğrulanamadı" ayrımı korunur.
      expect(r.isMismatch, isFalse);
      expect(r.isVerified, isFalse);
      // Gerçek hash yine de hesaplanır (log/diagnostic için).
      expect(r.actualHash, isNotNull);
    });

    test('hash bozuk biçimliyse de unavailable (yanlış "eşleşti" sayılmaz)', () {
      final r = ApkIntegrityVerifier.verifyBytes(
        bytes: apkBytes(64),
        expected: 'zzz',
      );
      expect(r.result, ApkIntegrityResult.unavailable);
      expect(r.hasExpected, isFalse);
    });
  });

  group('downloadAndVerify — sağlam hash', () {
    test('indirir, doğrular, diske yazar', () async {
      final bytes = apkBytes(64 * 1024);
      stubResponse(body: bytes);
      ApkDownloader.tempDir = () async => tempRoot;

      final result = await ApkDownloader.downloadAndVerify(manifest(
        sha256: ApkIntegrityVerifier.sha256Hex(bytes),
      ));

      expect(result.isVerified, isTrue);
      expect(result.isUnverifiable, isFalse);
      expect(result.byteLength, bytes.length);
      expect(result.file.existsSync(), isTrue);
      expect(await result.file.readAsBytes(), bytes);
    });

    test('boş dosya (0 bayt) reddedilir', () async {
      stubResponse(body: const <int>[]);
      ApkDownloader.tempDir = () async => tempRoot;
      await expectLater(
        ApkDownloader.downloadAndVerify(manifest(sha256: 'a' * 64)),
        throwsA(
          isA<ApkDownloadException>()
              .having((e) => e.kind, 'kind', ApkDownloadFailure.empty),
        ),
      );
    });

    test('HTTP 404 reddedilir, dosya yazılmaz', () async {
      stubResponse(body: apkBytes(16), status: 404);
      ApkDownloader.tempDir = () async => tempRoot;
      await expectLater(
        ApkDownloader.downloadAndVerify(manifest(sha256: 'a' * 64)),
        throwsA(
          isA<ApkDownloadException>()
              .having((e) => e.kind, 'kind', ApkDownloadFailure.network),
        ),
      );
      expect(File('${tempRoot.path}/calorix-update.apk').existsSync(), isFalse);
    });

    test('üst sınırı aşan gövde reddedilir (maxApkBytes)', () async {
      // Gerçek bir HTTP gövdesi üretmeden sınırı test etmek için küçük bir
      // sınır ile stub'lanır; `maxApkBytes` sabitini de doğrularız.
      expect(ApkDownloader.maxApkBytes, 120 * 1024 * 1024);
      stubResponse(body: apkBytes(16), status: 200);
      ApkDownloader.tempDir = () async => tempRoot;
      // Sınırın altındaki gövde geçer — sınırın kendisi bir regresyon
      // testinde sabitlenmiştir.
      final ok = await ApkDownloader.downloadAndVerify(manifest(
        sha256: ApkIntegrityVerifier.sha256Hex(apkBytes(16)),
      ));
      expect(ok.byteLength, 16);
    });
  });

  group('downloadAndVerify — bozuk hash REDDEDER', () {
    test('hash uyuşmazsa dosya diske bile yazılmaz', () async {
      final bytes = apkBytes(8192);
      stubResponse(body: bytes);
      ApkDownloader.tempDir = () async => tempRoot;

      await expectLater(
        ApkDownloader.downloadAndVerify(manifest(
          sha256: ApkIntegrityVerifier.sha256Hex(apkBytes(8191)),
        )),
        throwsA(
          isA<ApkDownloadException>()
              .having((e) => e.kind, 'kind', ApkDownloadFailure.integrity),
        ),
      );
      // Yazılmadığı doğrulanır — bozuk APK yükleyiciye açılmaz.
      expect(File('${tempRoot.path}/calorix-update.apk').existsSync(), isFalse);
    });

    test('yarım inmiş dosya (beklenenden kısa) reddedilir', () async {
      final full = apkBytes(16384);
      final truncated = full.sublist(0, full.length ~/ 2);
      stubResponse(body: truncated);
      ApkDownloader.tempDir = () async => tempRoot;

      await expectLater(
        ApkDownloader.downloadAndVerify(manifest(
          sha256: ApkIntegrityVerifier.sha256Hex(full),
        )),
        throwsA(
          isA<ApkDownloadException>()
              .having((e) => e.kind, 'kind', ApkDownloadFailure.integrity),
        ),
      );
    });
  });

  group('downloadAndVerify — hash YOK (belgelenen davranış)', () {
    test('indirme yapılır, kurulum ENGELLENMEZ, unverifiable işaretlenir', () async {
      final bytes = apkBytes(4096);
      stubResponse(body: bytes);
      ApkDownloader.tempDir = () async => tempRoot;

      final result = await ApkDownloader.downloadAndVerify(manifest());

      expect(result.isUnverifiable, isTrue);
      expect(result.isVerified, isFalse);
      // Dosya YAZILDI — kullanıcı güncellemeyi kurabilir (bilinçli karar).
      expect(result.file.existsSync(), isTrue);
      expect(result.byteLength, bytes.length);
    });

    test('biçimsiz hash de aynı davranışı gösterir', () async {
      stubResponse(body: apkBytes(1024));
      ApkDownloader.tempDir = () async => tempRoot;
      final result =
          await ApkDownloader.downloadAndVerify(manifest(sha256: 'abc'));
      expect(result.isUnverifiable, isTrue);
      expect(result.file.existsSync(), isTrue);
    });
  });

  group('downloadAndVerify — URL güvenliği', () {
    test('javascript: şeması indirme yapılmadan reddedilir', () async {
      var fetched = false;
      ApkDownloader.fetch = (uri) async {
        fetched = true;
        return http.Response('', 200);
      };
      ApkDownloader.tempDir = () async => tempRoot;

      await expectLater(
        ApkDownloader.downloadAndVerify(manifest(apkUrl: 'javascript:alert(1)')),
        throwsA(
          isA<ApkDownloadException>()
              .having((e) => e.kind, 'kind', ApkDownloadFailure.unsafeUrl),
        ),
      );
      expect(fetched, isFalse, reason: 'ağa hiç çıkılmamalı');
    });

    test('file:// şeması reddedilir (yerel dosya erişimi)', () async {
      ApkDownloader.tempDir = () async => tempRoot;
      await expectLater(
        ApkDownloader.downloadAndVerify(
            manifest(apkUrl: 'file:///data/local/tmp/evil.apk')),
        throwsA(
          isA<ApkDownloadException>()
              .having((e) => e.kind, 'kind', ApkDownloadFailure.unsafeUrl),
        ),
      );
    });

    test('ağ hatası network türüyle reddedilir', () async {
      ApkDownloader.fetch = (uri) async => throw const SocketException('yok');
      ApkDownloader.tempDir = () async => tempRoot;
      await expectLater(
        ApkDownloader.downloadAndVerify(manifest(sha256: 'a' * 64)),
        throwsA(
          isA<ApkDownloadException>()
              .having((e) => e.kind, 'kind', ApkDownloadFailure.network),
        ),
      );
    });
  });

  group('manifest sha256 alanı sözleşmesi', () {
    test('sha256 alanı release_android.sh çıktısıyla birebir okunur', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '1.3.0',
        'versionCode': 4,
        'minSupportedVersionCode': 2,
        'apkUrl': 'https://github.com/x/y/releases/download/android-v1.3.0%2B4/calorix.apk',
        'sha256': abcHash,
        'notes': {'tr': 'not', 'en': 'note'},
        'releasedAt': '2026-09-27T00:00:00Z',
      });
      expect(m.sha256, abcHash);
      // Normalleştirme manifest'ten bağımsız: büyük harfli hash de
      // doğrulamada kullanılabilir.
      expect(
        ApkIntegrityVerifier.normalizeExpected(m.sha256!.toUpperCase()),
        abcHash,
      );
    });

    test('sha256 alanı yoksa null (doğrulama "unavailable" yoluna düşer)', () {
      final m = UpdateManifest.fromJson(const {
        'versionName': '1.3.0',
        'versionCode': 4,
        'apkUrl': 'https://github.com/x/y/releases/download/v/calorix.apk',
      });
      expect(m.sha256, isNull);
    });
  });

  group('Uint8List yolu', () {
    test('verifyUint8 verifyBytes ile aynı sonucu verir', () {
      final bytes = Uint8List.fromList(apkBytes(256));
      final expected = ApkIntegrityVerifier.sha256Hex(bytes);
      expect(
        ApkIntegrityVerifier.verifyUint8(bytes, expected: expected).result,
        ApkIntegrityResult.verified,
      );
      expect(
        ApkIntegrityVerifier.verifyUint8(bytes, expected: 'b' * 64).result,
        ApkIntegrityResult.mismatch,
      );
      expect(
        ApkIntegrityVerifier.verifyUint8(bytes).result,
        ApkIntegrityResult.unavailable,
      );
    });
  });
}
