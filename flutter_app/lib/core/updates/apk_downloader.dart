import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../observability/app_logger.dart';
import 'apk_integrity.dart';
import 'update_manifest.dart';

/// APK indirme + `sha256` doğrulama akışı.
///
/// ## Neden ayrı bir indirme akışı?
///
/// Mevcut akış `apkUrl`'yi `url_launcher`'a (harici tarayıcı) veriyordu:
/// uygulama dosyanın **içeriğini hiç görmüyor**. `latest.json`'daki `sha256`
/// alanı bu yüzden doğrulanamıyordu. Burada indirme uygulama içinde yapılır,
/// hash karşılaştırılır ve dosya **yalnızca doğrulandıktan sonra** Android
/// yükleyicisine açılır.
///
/// ## Hash yoksa davranış (bilinçli karar)
///
/// Reddetmek zorunlu güncellemede kullanıcıyı geri dönüşsüz kilitler
/// (hash'i olmayan herhangi bir release'te uygulama hiç güncellenemez).
/// Bu yüzden hash yoksa indirme **engellenmez**, [ApkIntegrityResult.unavailable]
/// ile işaretlenir ve çağıran bunu kullanıcıya **uyarı** olarak gösterir.
/// Hash **var** ve tutmuyorsa indirme **reddedilir** (dosya açılmaz).
abstract final class ApkDownloader {
  /// Üst sınır: release APK'sı tipik olarak 15–40 MB. MITM/bozuk sunucu
  /// için `bodyBytes` sınırsız belleğe alınmamalı. Aşılırsa indirme iptal
  /// edilir (dosya diske yazılmaz).
  static const int maxApkBytes = 120 * 1024 * 1024;

  /// Ağ zaman aşımı — büyük dosyada bağlantı kurma + ilk bayt süresi.
  static const Duration timeout = Duration(seconds: 30);

  /// Testlerde platform eklentilerini (path_provider, http) değiştirebilmek
  /// için enjekte edilebilir sarmalayıcılar.
  static Future<http.Response> Function(Uri uri) fetch = (uri) => http.get(
        uri,
        headers: {'Accept': 'application/vnd.android.package-archive'},
      );

  /// Geçici dosya dizini (`getTemporaryDirectory`). Testte geçici dizin
  /// (`Directory.systemTemp`) ile değiştirilir.
  static Future<Directory> Function() tempDir = () => getTemporaryDirectory();

  /// Test sonrası orijinal implementasyonlara dön.
  static void reset() {
    fetch = (uri) => http.get(
          uri,
          headers: {'Accept': 'application/vnd.android.package-archive'},
        );
    tempDir = () async => getTemporaryDirectory();
  }

  /// [manifest]'teki APK'yı indirir ve `sha256` ile doğrular.
  ///
  /// Başarılıysa indirilmiş dosyanın yolunu döner — `apkUrl` süzgecinden
  /// geçmeyen manifest için **hiç indirme yapılmaz**.
  /// Hata durumunda [ApkDownloadException] fırlatır.
  static Future<ApkDownloadResult> downloadAndVerify(UpdateManifest manifest) async {
    if (!manifest.isApkUrlSafe) {
      throw const ApkDownloadException(
        kind: ApkDownloadFailure.unsafeUrl,
        message: 'Güvensiz APK adresi reddedildi',
      );
    }

    final http.Response response;
    try {
      response = await fetch(Uri.parse(manifest.apkUrl.trim())).timeout(timeout);
    } on TimeoutException {
      throw const ApkDownloadException(
        kind: ApkDownloadFailure.network,
        message: 'İndirme zaman aşımına uğradı',
      );
    } catch (e, s) {
      AppLog.w('APK indirilemedi', e, s);
      throw const ApkDownloadException(
        kind: ApkDownloadFailure.network,
        message: 'APK indirilemedi',
      );
    }

    if (response.statusCode != 200) {
      throw ApkDownloadException(
        kind: ApkDownloadFailure.network,
        message: 'HTTP ${response.statusCode}',
      );
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw const ApkDownloadException(
        kind: ApkDownloadFailure.empty,
        message: 'APK boş indirildi',
      );
    }
    if (bytes.length > maxApkBytes) {
      throw ApkDownloadException(
        kind: ApkDownloadFailure.tooLarge,
        message: 'APK beklenenden büyük (${bytes.length} bayt)',
      );
    }

    final integrity =
        ApkIntegrityVerifier.verifyUint8(bytes, expected: manifest.sha256);

    if (integrity.isMismatch) {
      // Bozuk/değiştirilmiş indirme: dosya diske bile yazılmaz.
      AppLog.w(
        'APK sha256 uyuşmadi (beklenen=${integrity.expectedHash}, '
        'gerçek=${integrity.actualHash})',
      );
      throw const ApkDownloadException(
        kind: ApkDownloadFailure.integrity,
        message: 'APK bütünlük doğrulaması başarısız',
      );
    }

    // Hash yoksa `unavailable` → yine de yazılır ve açılabilir (uyarı gösterilir).
    final dir = await tempDir();
    final file = File('${dir.path}/calorix-update.apk');
    await file.writeAsBytes(bytes, flush: true);

    return ApkDownloadResult(
      file: file,
      integrity: integrity,
      byteLength: bytes.length,
    );
  }
}

/// Kurulum akışının son durumu — UI katmanı bunu çeviri anahtarına bağlar.
enum ApkInstallStatus {
  /// APK indirildi, `sha256` doğrulandı ve yükleyici açıldı.
  opened,

  /// APK indirildi ve yükleyici açıldı ama **hash doğrulanamadı** (manifest'te
  /// yok). Kurulum devam eder, kullanıcı uyarılır.
  openedUnverified,

  /// Yükleyici açılamadı (`launchUrl` false döndü — Android 8+ PACKAGE_INSTALLER
  /// izni verilmemiş olabilir).
  launchFailed,

  /// İndirme başarısız (ağ/boş/hâlâ).
  downloadFailed,

  /// Hash var ama **eşleşmiyor** — indirme reddedildi, dosya açılmadı.
  integrityFailed,

  /// `apkUrl` güvenli değil — indirme hiç yapılmadı.
  unsafeUrl,

  /// APK manifestin belirttiğinden büyük.
  tooLarge,
}

/// [ApkDownloader] + yükleyici açma zincirinin sonucu.
@immutable
class ApkInstallOutcome {
  const ApkInstallOutcome({required this.status, this.integrity, this.message});

  final ApkInstallStatus status;

  /// Doğrulama sonucu — [ApkInstallStatus.opened] dışında `null` olabilir.
  final ApkIntegrity? integrity;

  /// Tanısal mesaj (log için, kullanıcıya gösterilmez).
  final String? message;

  bool get opened =>
      status == ApkInstallStatus.opened ||
      status == ApkInstallStatus.openedUnverified;

  bool get openedWithoutHash => status == ApkInstallStatus.openedUnverified;
}

/// İndirme sonucunu taşıyan sınıf.
@immutable
class ApkDownloadResult {
  const ApkDownloadResult({
    required this.file,
    required this.integrity,
    required this.byteLength,
  });

  final File file;
  final ApkIntegrity integrity;
  final int byteLength;

  bool get isVerified => integrity.isVerified;
  bool get isUnverifiable => integrity.result == ApkIntegrityResult.unavailable;
}

/// İndirme başarısızlık türleri — kullanıcıya hangi mesajın gösterileceğini
/// belirler.
enum ApkDownloadFailure { unsafeUrl, network, empty, tooLarge, integrity, write }

/// İndirme/doğrulama hatası.
class ApkDownloadException implements Exception {
  const ApkDownloadException({required this.kind, required this.message});

  final ApkDownloadFailure kind;
  final String message;

  @override
  String toString() => 'ApkDownloadException($kind): $message';
}
