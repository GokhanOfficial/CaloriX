import 'package:calorix/core/notifications/timezone_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Saat dilimi çözümlemesi ve günlük tetikleme hesabı.
///
/// `flutter_local_notifications` + `timezone` gerçek planlama zinciri
/// cihaz/method-channel gerektirir; buradaki çekirdek saf Dart'tır ve
/// sessiz UTC kayması ile DST gün/gün kaymasını kilitler.
void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('resolveTimeZone', () {
    test('IANA adı doğrudan çözülür', () {
      expect(resolveTimeZone('Europe/Istanbul')?.name, 'Europe/Istanbul');
      expect(resolveTimeZone('Europe/Berlin')?.name, 'Europe/Berlin');
    });

    test('baştaki/ sondaki boşluk temizlenir', () {
      expect(resolveTimeZone('  Europe/Istanbul  ')?.name, 'Europe/Istanbul');
    });

    test('GMT+03:00 sabit ofseti Etc/GMT-3 olarak çözülür', () {
      // POSIX ters işaret: Etc/GMT-3 == UTC+03:00.
      expect(resolveTimeZone('GMT+03:00')?.name, 'Etc/GMT-3');
    });

    test('UTC+3 / +03:00 / GMT-5 biçimleri çözülür', () {
      expect(resolveTimeZone('UTC+3')?.name, 'Etc/GMT-3');
      expect(resolveTimeZone('+03:00')?.name, 'Etc/GMT-3');
      expect(resolveTimeZone('+3')?.name, 'Etc/GMT-3');
      expect(resolveTimeZone('GMT-5')?.name, 'Etc/GMT+5');
    });

    test('dakika hassasiyetli sabit ofset çözülemez (belgelenmiş sınır)', () {
      // Etc/GMT±N veritabanında tam saatten ibarettir; +05:45 gibi bir
      // sabit ofset çözülemez → null (çağıran loglar, sessiz UTC yok).
      expect(resolveTimeZone('+05:45'), isNull);
      expect(resolveTimeZone('GMT+05:45'), isNull);
    });

    test('sıfır ofset UTC olarak çözülür', () {
      expect(resolveTimeZone('GMT+00:00')?.name, 'UTC');
      expect(resolveTimeZone('+0')?.name, 'UTC');
    });

    test('null / boş / çöp girdi null döner (sessizce UTC\'ye düşmez)', () {
      expect(resolveTimeZone(null), isNull);
      expect(resolveTimeZone(''), isNull);
      expect(resolveTimeZone('   '), isNull);
      expect(resolveTimeZone('Bilinmeyen/Dilim'), isNull);
      expect(resolveTimeZone('GMT+99:00'), isNull);
    });

    test('bulunamayan dilim tz.local\'i değiştirmez', () {
      final before = tz.local.name;
      resolveTimeZone('Olmayan/Dilim');
      expect(tz.local.name, before);
    });
  });

  group('nextDailyOccurrence', () {
    /// Verilen yerel saati temsil eden TZDateTime kurar.
    tz.TZDateTime at(String zone, int y, int m, int d, int hh, int mm) {
      tz.setLocalLocation(tz.getLocation(zone));
      return tz.TZDateTime(tz.getLocation(zone), y, m, d, hh, mm);
    }

    test('henüz gelmemiş saat → bugün aynı gün', () {
      final now = at('Europe/Istanbul', 2026, 9, 27, 7, 0);
      final when = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(when.year, 2026);
      expect(when.month, 9);
      expect(when.day, 27);
      expect(when.hour, 8);
      expect(when.minute, 30);
    });

    test('geçmiş saat → ertesi gün (aynı saat)', () {
      final now = at('Europe/Istanbul', 2026, 9, 27, 23, 0);
      final when = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(when.day, 28);
      expect(when.hour, 8);
      expect(when.minute, 30);
    });

    test('tam eşleşen saat geçmiş sayılır → ertesi gün', () {
      // `isAfter` kesin: == değil → ileride değilse ertesi güne atılır.
      final now = at('Europe/Istanbul', 2026, 9, 27, 8, 30);
      final when = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(when.day, 28);
    });

    test('ay sonu geçişi: 31 Ekim 23:00 + 08:30 → 1 Kasım', () {
      final now = at('Europe/Istanbul', 2026, 10, 31, 23, 0);
      final when = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(when.month, 11);
      expect(when.day, 1);
      expect(when.hour, 8);
    });

    test('dilim değişimi sonrası hedef saat yeni dilimde sabit kalır', () {
      // 08:30 istanbul → 09:30 Berlin. `add(Duration(days: 1))` mutlak
      // 24 saat eklendiği için yaz saati sınırında 1 saat kayardı;
      // `TZDateTime(...)` yeniden kurulumu hedef duvar saatini korur.
      final now = at('Europe/Istanbul', 2026, 3, 28, 20, 0);
      final when = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      // 29 Mart 2026'da Berlin +02:00'e geçiyor; 08:30 Berlin = 09:30 TR.
      expect(when.hour, 8);
      expect(when.minute, 30);
      expect(when.day, 29);
    });

    test('sonuç daima gelecekte (now\'dan sonra)', () {
      for (final hour in [0, 6, 12, 18, 23]) {
        final now = at('Europe/Istanbul', 2026, 5, 10, hour, 15);
        for (final target in [0, 9, 12, 23]) {
          final when =
              nextDailyOccurrence(now: now, hour: target, minute: 0);
          expect(
            when.isAfter(now),
            isTrue,
            reason: 'now.hour=$hour target=$target → ${when.toIso8601String()}',
          );
        }
      }
    });
  });
}
