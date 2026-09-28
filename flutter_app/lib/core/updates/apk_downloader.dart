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

  /// Geçici APK dosyasının ad öneki.
  static const String stagedFilePrefix = 'calorix-update-';

  /// Geçici APK dosyasının adı — sürüm ve kod ile ayrıştırılır.
  ///
  /// Sabit ad (`calorix-update.apk`) yerine sürümlü ad kullanılıyor:
  /// kullanıcı güncellemeyi iptal ettiğinde (yükleyiciyi kapattı) dosya
  /// diskte kalıyordu ve aynı ad kullanıldığı için sonraki denemede
  /// sessizce eziliyordu. Sürümlü ad, "hangi sürüm indirildi" ayrımını
  /// dosya adından okunur kılar ve [_deleteStaleSiblings] eskiyi temizler.
  static String stagedFileName(UpdateManifest manifest) {
    // `..` ve ayraçlar ayrıca engellenir: sürüm adı `..` içerirse
    // `.._.._evil` gibi bir ad üretilir ve `File('${dir.path}/$name')`
    // yine de dizin dışına kaçamaz, ama "temizlenmesi gereken eski dosya"
    // süzgeci için belirsizlik yaratır.
    final safeVersion = manifest.versionName
        .replaceAll('..', '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$stagedFilePrefix${manifest.versionCode}-$safeVersion.apk';
  }

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
    final name = stagedFileName(manifest);
    final file = File('${dir.path}/$name');
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (e, s) {
      // Disk dolu / izin yok: yarım kalan dosyayı temizle, yoksa bir sonraki
      // denemede `file://` üzerinden **yarım APK** yükleyiciye açılabilir.
      AppLog.w('APK diske yazılamadı', e, s);
      _deleteQuietly(file);
      throw const ApkDownloadException(
        kind: ApkDownloadFailure.write,
        message: 'APK kaydedilemedi',
      );
    }
    // Önceki sürümden kalmış dosyaları temizle (disk dolmasın).
    _deleteStaleSiblings(dir, keepName: name);

    return ApkDownloadResult(
      file: file,
      integrity: integrity,
      byteLength: bytes.length,
    );
  }

  /// Geçici dizindeki eski sürüm artıklarını temizler.
  ///
  /// `calorix-update.apk` **sabit bir ad** kullanıyor; her indirme aynı
  /// dosyayı ezer. Bu tek dosya kendiliğinden sınırsız büyümez, ama:
  ///  * kullanıcı güncellemeyi iptal ederse (yükleyiciyi kapatır) dosya
  ///    diskte kalır ve güncelleme sürümü değişene kadar (haftalar) yer
  ///    kaplar,
  ///  * indirme başarısız olduğunda yarım dosya kalabilirdi.
  ///
  /// `stagedFileName` (sürüm + kod) adlandırması, sürüm başına en fazla bir
  /// dosya tutar; eskiler ilk başarılı indirmede silinir.
  static void _deleteStaleSiblings(
    Directory dir, {
    required String keepName,
  }) {
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (!name.startsWith(stagedFilePrefix) || name == keepName) continue;
        _deleteQuietly(entity);
      }
    } catch (e, s) {
      // Temizlik başarısız olursa indirme yine de geçerli — sadece disk
      // biraz daha dolu kalır.
      AppLog.w('Eski APK geçici dosyaları temizlenemedi', e, s);
    }
  }

  static void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Disk yazma/erişim hatası: dosya kalır, sonraki indirme üzerine yazar.
    }
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
