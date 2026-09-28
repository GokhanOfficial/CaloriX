/// GitHub Releases'ta tutulan `latest.json` manifesti — Android zorunlu
/// güncelleme kontrolünün veri modeli ve saf karar mantığı.
///
/// `minSupportedVersionCode`: altındaki sürümler çalışamaz (DB migration'ı
/// geldiğinde `tool/release_android.sh --min-code N` ile yükseltilir).
class UpdateManifest {
  const UpdateManifest({
    required this.versionName,
    required this.versionCode,
    required this.minSupportedVersionCode,
    required this.apkUrl,
    this.sha256,
    this.notesTr,
    this.notesEn,
    this.releasedAt,
  });

  final String versionName;
  final int versionCode;
  final int minSupportedVersionCode;
  final String apkUrl;

  /// APK'nın SHA-256 özeti (hex). `tool/release_android.sh` her release'de
  /// `sha256sum` ile yazar. Doğrulama `core/updates/apk_integrity.dart`
  /// içindedir; **eksikse reddetmek yerine "doğrulanamaz" sayılır**
  /// (gerekçe: `apk_integrity.dart` başlığındaki karar notu).
  final String? sha256;

  /// Sürüm notları (release notes) — mevcut dile göre seçilir.
  final String? notesTr;
  final String? notesEn;
  final String? releasedAt;

  /// Yoksa 1: tüm eski sürümler opsiyonel güncelleme görür (zorunluluk
  /// yalnızca açıkça cutoff girildiğinde devreye girer).
  static const int _defaultMinSupported = 1;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    // `versionCode` elle düzenlenmiş bir manifest'te `7.0` (double) gelebilir.
    // `as int` bu durumda `TypeError` fırlatıyor ve `check()` catch'e
    // düşüp **önbelleğe** geri dönüyordu — yani geçerli bir manifest
    // yüzünden uygulama eski sürüm kararını kullanmaya devam ediyordu.
    // Toleranslı parse: tam sayıya yakın double kabul, kesirli/çöp red.
    final rawVersionCode = json['versionCode'];
    final versionCode = switch (rawVersionCode) {
      final int v => v,
      final num v when v == v.roundToDouble() => v.toInt(),
      _ => throw FormatException(
          'versionCode sayı olmalı, alınan: ${rawVersionCode.runtimeType}'),
    };
    return UpdateManifest(
      versionName: json['versionName'] as String,
      versionCode: versionCode,
      minSupportedVersionCode:
          _intOr(json['minSupportedVersionCode']) ?? _defaultMinSupported,
      apkUrl: json['apkUrl'] as String,
      sha256: json['sha256'] as String?,
      notesTr: (json['notes'] as Map<String, dynamic>?)?['tr'] as String?,
      notesEn: (json['notes'] as Map<String, dynamic>?)?['en'] as String?,
      releasedAt: json['releasedAt'] as String?,
    );
  }

  /// `int` alanı toleranslı okur: `7` ve `7.0` kabul, `7.5` / `"7"` / `null`
  /// için `null` döner (çağıran varsayılanı kullanır).
  static int? _intOr(Object? value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return null;
  }

  /// APK adresi **güvenli mi**? (https + APK dosya uzantısı)
  ///
  /// Manifest, uzak bir sunucudan (GitHub Releases) gelen veridir ve
  /// `apkUrl` doğrudan `url_launcher`'a verilir. Doğrulama olmadan
  /// `javascript:`, `intent:`, `file:` gibi şemalar `canLaunchUrl`
  /// üzerinden dış uygulamaya açılabilir (açık yönlendirme / yerel dosya
  /// erişimi). `tool/release_android.sh` yalnızca
  /// `https://github.com/<repo>/releases/download/.../calorix.apk`
  /// ürettiği için bu süzgeç meşru dağıtımı engellemez.
  bool get isApkUrlSafe => isSafeApkUrl(apkUrl);

  /// [UpdateManifest.isApkUrlSafe] için saf sürüm — test edilebilir.
  static bool isSafeApkUrl(String raw) {
    final url = Uri.tryParse(raw.trim());
    if (url == null) return false;
    if (url.scheme != 'https') return false;
    if (url.host.isEmpty) return false;
    // Kullanıcı/parola gömülü URL'ler (https://user:pass@host) reddedilir.
    if (url.userInfo.isNotEmpty) return false;
    return url.path.toLowerCase().endsWith('.apk');
  }

  /// Aktif dile uygun sürüm notu (yoksa null).
  ///
  /// `??` zinciri tek başına **boş string'i** geçirirdi
  /// (`notes: {tr: '', en: 'not'}` iken `notesFor('tr')` → `''`, UI'da boş
  /// "Bu sürümde" kartı). Boş string de "yok" sayılır.
  String? notesFor(String languageCode) {
    final preferred = languageCode.startsWith('tr') ? notesTr : notesEn;
    if (preferred != null && preferred.isNotEmpty) return preferred;
    final fallback = languageCode.startsWith('tr') ? notesEn : notesTr;
    return (fallback != null && fallback.isNotEmpty) ? fallback : null;
  }
}

/// Cihaz sürümüne göre güncelleme kararı.
enum UpdateDecision {
  /// Cihaz sürümü `minSupportedVersionCode` altında — açılış engellenir.
  required,

  /// Yeni sürüm var ama cihaz sürümü hâlâ destekleniyor — atlanabilir hatırlatma.
  optional,

  /// Cihaz en yeni sürümde.
  upToDate,
}

/// Saf karar fonksiyonu — [UpdateManifest.evaluate] ile aynı mantık,
/// testlerde doğrudan kullanılır.
UpdateDecision decideUpdate({
  required int deviceVersionCode,
  required int minSupportedVersionCode,
  required int latestVersionCode,
}) {
  if (deviceVersionCode < minSupportedVersionCode) {
    return UpdateDecision.required;
  }
  if (deviceVersionCode < latestVersionCode) {
    return UpdateDecision.optional;
  }
  return UpdateDecision.upToDate;
}

extension UpdateManifestEval on UpdateManifest {
  /// Cihaz build numarasına göre güncelleme kararı.
  UpdateDecision evaluate(int deviceVersionCode) => decideUpdate(
        deviceVersionCode: deviceVersionCode,
        minSupportedVersionCode: minSupportedVersionCode,
        latestVersionCode: versionCode,
      );
}
