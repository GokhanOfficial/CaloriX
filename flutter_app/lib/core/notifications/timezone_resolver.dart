import 'package:timezone/timezone.dart' as tz;

/// Cihaz saat dilimi adını `timezone` veritabanındaki bir konuma çözer.
///
/// Neden gerekli: `timezone` paketinde `tz.local` başlangıçta **UTC**'dir
/// (`initializeTimeZones()` yalnızca `tz.local = UTC` atar). `flutter_timezone`
/// Android/iOS'tan IANA adı (`Europe/Istanbul`) döndürür ama bazı build'ler
/// sabit ofset biçimi (`GMT+03:00`, `+03:00`, `UTC+3`) döndürebilir. Bu
/// girdiler `tz.getLocation` içinde `LocationNotFoundException` fırlatır ve
/// önceki `catch (_)` bunu yutarak tüm hatırlatıcıları sessizce UTC'de
/// planlıyordu.
///
/// Dönen `null`, konumun çözülemediği anlamına gelir — çağıran bunu
/// loglamak zorundadır, sessizce UTC'ye düşmemelidir.
tz.Location? resolveTimeZone(String? platformZone) {
  if (platformZone == null) return null;
  final name = platformZone.trim();
  if (name.isEmpty) return null;
  final direct = _tryGetLocation(name);
  if (direct != null) return direct;
  final fixed = _fixedOffsetZoneName(name);
  return fixed == null ? null : _tryGetLocation(fixed);
}

/// `Etc/GMT-3` gibi POSIX ters işaretli adları üretir; saat dilimi
/// biçimi değilse `null`.
///
/// Yalnızca **tam saat** ofsetleri karşılanır: `Etc/GMT±N` veritabanında
/// dakika hassasiyeti yoktur (`+05:45`, `-03:30` gibi Asya/Güney Amerika
/// dilimleri `Etc/` altında bulunmaz). Bu girdiler IANA veritabanında zaten
/// gerçek bir adla (`Asia/Kathmandu`) döner; yalnızca tam saat dışı **sabit**
/// ofset bildiren cihazlar çözülemez ve `null` döner — çağıran bunu
/// loglamak zorundadır, sessizce UTC'ye düşmemelidir.
String? _fixedOffsetZoneName(String name) {
  // "GMT+03:00" / "UTC+3" / "+03:00" / "+3"
  final m = RegExp(
    r'^(?:GMT|UTC)?\s*([+-])(\d{1,2})(?::?(\d{2}))?$',
  ).firstMatch(name);
  if (m == null) return null;
  final sign = m.group(1)!;
  final hours = int.parse(m.group(2)!);
  final minutes = int.parse(m.group(3) ?? '0');
  if (hours > 14 || minutes > 59) return null;
  if (minutes != 0) return null;
  if (hours == 0) return 'UTC';
  // Etc/GMT zones cover -12..+14 but POSIX sign is inverted.
  final inverted = sign == '+' ? '-' : '+';
  final candidate = 'Etc/GMT$inverted$hours';
  return _tryGetLocation(candidate) != null ? candidate : null;
}

tz.Location? _tryGetLocation(String name) {
  if (name.isEmpty) return null;
  try {
    return tz.getLocation(name);
  } on tz.LocationNotFoundException {
    return null;
  }
}

/// Verilen saat için **bir sonraki** günlük tetikleme anı.
///
/// Önceki kod `when.add(const Duration(days: 1))` ile bir gün ileri atıyordu;
/// bu **duvar saati değil mutlak süre** eklediği için DST geçişlerinde plan
/// 1 saat kayıyordu (Türkiye'de bile geçmişte +1 saat, AB'de ±1 saat).
/// Burada `TZDateTime(tz.local, …)` her gün için **yeniden** oluşturulur; boylece
/// hedef saat dilimde mevcut değilse (yaz saati boşluğu) `tz` paketinin
/// standart çözümlemesi uygulanır ve sonraki gün doğru saate düşer.
///
/// [hour]/[minute] aralık dışıysa değer `DateTime` normalizasyonuyla
/// kaydırılır (ör. 25:30 → ertesi gün 01:30).
tz.TZDateTime nextDailyOccurrence({
  required tz.TZDateTime now,
  required int hour,
  required int minute,
}) {
  var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  if (!when.isAfter(now)) {
    when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + 1,
      hour,
      minute,
    );
  }
  return when;
}
