/// Veri katmanının ortak sayı/tarih okuma yardımcıları.
///
/// Neden ayrı dosya: `_num` / `_numOrNull` (bozuk sayıyı 0'a düşüren okuyucu)
/// ve `yyyy-MM-dd` biçimlendirme **iki ayrı repository'de** kopyalanmıştı
/// (`analytics_repository.dart` + `macro_calculator.dart`, `diary_repository.dart`
/// + `chat_repository.dart`). Yeni bir repository aynı deseni kopyalarsa
/// davranış sessizce ayrışır; tek uygulama burada toplanır.
///
/// Bu dosya `lib/core/utils/` altındadır ve `core/**` tarafından da
/// tüketilir: `data/repositories/diary_repository.dart` → `formatEntryDate`
/// bu dosyaya devrediyor, `core/widgets/widget_snapshot.dart` de
/// `formatEntryDate` üzerinden aynı uygulamayı kullanıyor. Yani
/// `core/widgets/**` içinde ikinci bir kopyası **yok** (A3r2 turunda
/// doğrulandı).
library;

import 'dart:math';

/// JSON/DB değerini güvenli `double`'a çevirir.
///
/// Edge function yanıtları ve PostgREST satırları `int`/`double` dönebilir
/// ama eksik alan `null`, elle yazılmış veri `String`, bozuk sayı
/// `NaN`/`Infinity` olabilir. `round()`/`roundToDouble()` `NaN` üzerinde
/// `UnsupportedError` fırlattığı için bu üç durum da sayısal hesaba
/// sokulmamalıdır.
///
/// * [fallback] — değer okunamaz/sonlu değilse dönecek sonuç (varsayılan `0`).
double numOr(Object? v, {double fallback = 0}) {
  if (v is! num) return fallback;
  final d = v.toDouble();
  return d.isFinite ? d : fallback;
}

/// [numOr] innullable karşılığı: okunamayan değer `null` verir.
///
/// "Bu alan zorunlu" ayrımı gereken yerlerde kullanılır — çağıran null
/// görünce veriyi geçersiz sayıp kendi yolunu (yerel formül gibi) seçer.
double? numOrNull(Object? v) {
  if (v is! num) return null;
  final d = v.toDouble();
  return d.isFinite ? d : null;
}

/// Takvim gününü `yyyy-MM-dd` biçimine çevirir (web `format(date,'yyyy-MM-dd')`).
///
/// `DateTime` UTC olsa da **yıl/ay/gün bileşenleri yerel takvimde okunur**,
/// böylece istemci saat dilimi ne olursa olsun `entry_date` (DATE kolonu)
/// ile tutarlı bir gün anahtarı üretilir.
String formatDateOnly(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// RFC 4122 sürüm 4 ( rastgele) UUID üretir — `crypto.randomUUID()` karşılığı.
///
/// Yeni bağımlılık eklememek için `dart:math` `Random.secure()` kullanılır;
/// web'de `Math.random` tabanlı sürümden farklı olarak işletim sisteminin
/// CSPRNG'sinden beslenir. Dosya adları için kullanıldığından çakışma
/// olasılığı pratikte ihmal edilebilir olsa da doğru v4/variant bitleri
/// konur (RFC 4122 §4.4).
///
/// NOT: Güvenlik açısından kritik değerlerde (parola, oturum, API anahtarı)
/// kullanılmamalıdır; Dart'ta platform kriptografik PRNG'si yoktur.
String randomUuidV4({Random? random}) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  // Sürüm 4: zaman damgası üst 4 bit '0100' → byte 6 = 0x4X
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Variant: RFC 4122 '10x' → byte 8'de üst 2 bit '10'
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}
