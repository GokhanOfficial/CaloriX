/// Sohbet **ekleri**: gönderim öncesi seçili dosya ve boyut sınırları —
/// `chat_page.dart`'den bölündü (A4r6, Tur 6).
///
/// ## Neden ayrı dosya
///
/// Sınırlar `ChatAttachmentLimits` adlı **saf** bir sınıf olarak zaten
/// `image_picker`'dan bağımsızdı ve testler doğrudan onu çağırıyor. Aynı
/// dosyada `ChatPage`'in 580 satırlık durum mantığı varken bu sınıfı
/// bulmak zordu; ayrı dosyada hem kural hem de seçili ek modeli tek yerde.
library;

import 'dart:typed_data';

/// Gönderimden önce seçili ek (web `File` karşılığı — byte'ları bellekte).
class PendingAttachment {
  const PendingAttachment({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// Sohbet eki boyut sınırları — tek dosya ve toplam.
///
/// Saf fonksiyon olarak tutulur: sınır kararı `image_picker`'a bağlı
/// olmadan (paket seçiciyi değiştirdiğinde sınır da unutulmasın diye)
/// doğrudan test edilebilir.
abstract final class ChatAttachmentLimits {
  /// Tek dosya üst sınırı (10 MB).
  static const int maxFileBytes = 10 * 1024 * 1024;

  /// Tüm eklerin toplam üst sınırı (25 MB).
  ///
  /// Tek dosya sınırı tek başına yetersiz: 3 × 10 MB = 30 MB ham byte
  /// bellekte tutuluyor ve `insertUserMessage` bunları base64'e çevirip
  /// (~1.33×) edge function gövdesine koyuyor → ~40 MB gövde.
  static const int maxTotalBytes = 25 * 1024 * 1024;

  /// Yeni ekin eklenip eklenemeyeceğini belirler.
  ///
  /// [pendingBytes] seçili eklerin mevcut toplamı, [newBytes] eklenmek
  /// istenen dosyanın boyutudur. Sınır **aşıldığında** reddedilir (eşitlik
  /// kabul edilir), böylece kullanıcının seçimi bozulmaz; eklenen dosya
  /// listeye hiç girmez.
  static bool canAccept({required int pendingBytes, required int newBytes}) {
    if (newBytes < 0 || pendingBytes < 0) return false;
    if (newBytes > maxFileBytes) return false;
    return pendingBytes + newBytes <= maxTotalBytes;
  }
}
