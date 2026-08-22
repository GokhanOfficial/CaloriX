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
  final String? sha256;

  /// Sürüm notları (release notes) — mevcut dile göre seçilir.
  final String? notesTr;
  final String? notesEn;
  final String? releasedAt;

  /// Yoksa 1: tüm eski sürümler opsiyonel güncelleme görür (zorunluluk
  /// yalnızca açıkça cutoff girildiğinde devreye girer).
  static const int _defaultMinSupported = 1;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) =>
      UpdateManifest(
        versionName: json['versionName'] as String,
        versionCode: json['versionCode'] as int,
        minSupportedVersionCode: (json['minSupportedVersionCode'] as int?) ??
            _defaultMinSupported,
        apkUrl: json['apkUrl'] as String,
        sha256: json['sha256'] as String?,
        notesTr: (json['notes'] as Map<String, dynamic>?)?['tr'] as String?,
        notesEn: (json['notes'] as Map<String, dynamic>?)?['en'] as String?,
        releasedAt: json['releasedAt'] as String?,
      );

  /// Aktif dile uygun sürüm notu (yoksa null).
  String? notesFor(String languageCode) =>
      languageCode.startsWith('tr') ? (notesTr ?? notesEn) : (notesEn ?? notesTr);
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
