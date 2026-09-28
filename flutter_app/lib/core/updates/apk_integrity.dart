import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// APK bütünlük doğrulaması — indirilen dosyanın `sha256`'ını GitHub
/// Releases manifestindeki `sha256` alanıyla karşılaştırır.
///
/// ## Neden gerekli
///
/// `latest.json` manifesti `apkUrl`'yi verir; APK `url_launcher` üzerinden
/// tarayıcıya/indirme yönlendiricisine açılır ve **kurulum tamamen Android
/// paket doğrulamasına** (varsa) bırakılır. `tool/release_android.sh` APK'nın
/// `sha256`'ını hesaplayıp manifest'e yazıyordu ama bu alan **hiç okunmuyordu**
/// (P2, Tur 1 bulgusu). Sonuç: yarım inen, bozulan veya değiştirilmiş bir APK
/// ile uygulama farkında olmadan aynı sürümü "doğru" sanıyor.
///
/// ## Hash yoksa ne olur?
///
/// **Bilinçli karar: hash yoksa doğrulama yapılamaz → reddedilmez, "doğrulanamaz"
/// olarak işaretlenir.** Gerekçe:
///
/// * Zorunlu güncellemede (`UpdateDecision.required`) hash reddi = kullanıcı
///   geri dönüşsüz kilitlenir. Bu, hash'li olmayan bir release'te (ör. geçmiş
///   `latest.json` dosyaları, elle yüklenen bir tag) uygulamayı tamamen
///   kullanılamaz hale getirir. Kilitlenme, bütünlük ihlaline göre daha kötü
///   bir arızadır.
/// * `latest.json`'u TLS ile GitHub'dan okuyoruz; saldırgan manifest'i
///   değiştirebiliyorsa hash'i de değiştirebilir (güven kökü ikisinde de
///   aynı). Yani hash, **eksik/bozuk indirmeye** karşı gerçek koruma
///   sağlar, **aktif saldırgana** karşı tek başına değil.
/// * Bu yüzden doğrulama "kapı" değil **"sinyal"** olarak tasarlandı:
///   [ApkIntegrity] sonucu her zaman üretilir, [UpdateGate] uyarı gösterir,
///   [ForceUpdatePage] güncellemeden önce uyarır.
///
/// Hash **var** ve **eşleşmiyorsa** indirme reddedilir — sessiz bir
/// bozulma kabul edilmez.
enum ApkIntegrityResult {
  /// Manifest'te hash yok (veya bozuk biçimli) — doğrulanamadı, engelleme yok.
  unavailable,

  /// Hash eşleşti — indirilen APK manifest'teki dosyadır.
  verified,

  /// Hash **var** ama indirilen dosyayla eşleşmiyor — indirme bozuk/değiştirilmiş.
  mismatch,
}

/// Bir APK indirmesinin bütünlük sonucu.
@immutable
class ApkIntegrity {
  const ApkIntegrity({
    required this.result,
    this.expectedHash,
    this.actualHash,
    this.byteLength,
  });

  /// Sonuç.
  final ApkIntegrityResult result;

  /// Manifest'teki beklenen hash (küçük harfe çevrilmiş, `null` ise yok).
  final String? expectedHash;

  /// Hesaplanan gerçek hash (`null` ise hesaplanamadı).
  final String? actualHash;

  /// Doğrulanan dosyanın boyutu (bayt) — hata ayıklama/log için.
  final int? byteLength;

  bool get isVerified => result == ApkIntegrityResult.verified;
  bool get isMismatch => result == ApkIntegrityResult.mismatch;

  /// Manifest hash'i var mı? (Yoksa [isMismatch] asla true olmaz.)
  bool get hasExpected => expectedHash != null;

  @override
  String toString() => 'ApkIntegrity($result, expected=$expectedHash, '
      'actual=$actualHash, bytes=$byteLength)';
}

/// Saf `sha256` yardımcıları — ağ/IO içermez, testlerde doğrudan çağrılabilir.
abstract final class ApkIntegrityVerifier {
  /// SHA-256 özeti 64 onaltılık karakterdir; karşılaştırma büyük/küçük
  /// harf ve boşluk duyarsızdır (`release_android.sh` `sha256sum` çıktısı
  /// küçük harf üretir ama elle yazılmış manifest'lerde büyük harf olabilir).
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Manifest hash'ini normalleştirir.
  ///
  /// `null`/`''`/bozuk biçim (64 hex değil) → `null`. **Yanlış kabul edilmez**:
  /// geçersiz bir hash "doğrulanamadı" anlamına gelir, "eşleşti" değil.
  static String? normalizeExpected(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;
    return _hex64.hasMatch(value) ? value : null;
  }

  /// Bayt dizisinin SHA-256 özeti (küçük harf hex).
  static String sha256Hex(List<int> bytes) =>
      sha256.convert(bytes).toString();

  /// Manifest hash'i ile indirilen baytları karşılaştırır.
  ///
  /// [expected] bozuksa sonuç [ApkIntegrityResult.unavailable]'dır — karşılaştırma
  /// yapılmaz. Bu, "hash yok" ile "hash var ama tutmuyor" ayrımını korur.
  static ApkIntegrity verifyBytes({
    required List<int> bytes,
    String? expected,
  }) {
    final normalized = normalizeExpected(expected);
    final actual = sha256Hex(bytes);
    if (normalized == null) {
      return ApkIntegrity(
        result: ApkIntegrityResult.unavailable,
        actualHash: actual,
        byteLength: bytes.length,
      );
    }
    return ApkIntegrity(
      result: actual == normalized
          ? ApkIntegrityResult.verified
          : ApkIntegrityResult.mismatch,
      expectedHash: normalized,
      actualHash: actual,
      byteLength: bytes.length,
    );
  }

  /// `Uint8List` (tipik olarak `response.bodyBytes`) için [verifyBytes].
  static ApkIntegrity verifyUint8(Uint8List bytes, {String? expected}) =>
      verifyBytes(bytes: bytes, expected: expected);
}
