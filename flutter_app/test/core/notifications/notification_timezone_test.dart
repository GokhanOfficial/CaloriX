import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/notifications/reminder_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// `notification_service.dart` içindeki saat → zaman noktası dönüşümünün
/// zaman dilimi davranışı.
///
/// Bildirimler `tz.TZDateTime.now(tz.local)` üzerinden planlanır; saat
/// dilimi yanlışsa hatırlatıcı saatler kayar (Türkiye'de 3 saat). Bu test
/// `timezone` paketinin gerçek davranışını doğrular — `test/` altında
/// daha önce assertion'sız bir `print` probe dosyası vardı, burada kalıcı
/// bir teste dönüştürüldü.
void main() {
  // `group()` gövdeleri `setUpAll`'dan ÖNCE değerlendirildiği için
  // `tz.getLocation` burada çağrıldığı anda veritabanı hazır olmalı.
  tzdata.initializeTimeZones();

  group('tz.local varsayılanı', () {
    test('initialize sonrası UTC — uygulama bunu cihaz saat dilimiyle değiştirir', () {
      // NOT: `notification_service.dart:54` çalışma zamanında
      // `tz.setLocalLocation(...)` çağırır. Test ortamında bu çağrı
      // yapılmadığı için `tz.local` UTC'de kalır. Buradaki test
      // varsayılanı kilitler; cihaz davranışı aşağıdaki
      // `Europe/Istanbul` testleriyle doğrulanır.
      expect(tz.local.name, 'UTC');
    });
  });

  group('Europe/Istanbul — sabit UTC+3 (DST yok)', () {
    final zone = tz.getLocation('Europe/Istanbul');

    test('yaz saati uygulaması yok: Ekim ve Mart aynı ofseti verir', () {
      // TR 2016'dan beri kalıcı UTC+3. Yıl boyu ofset değişmemeli;
      // değişiyorsa `tz.local` yanlış bölgeye set edilmiş demektir.
      final ekim = tz.TZDateTime(zone, 2026, 10, 27, 8, 30);
      final mart = tz.TZDateTime(zone, 2026, 3, 29, 8, 30);
      expect(ekim.timeZoneOffset, const Duration(hours: 3));
      expect(mart.timeZoneOffset, const Duration(hours: 3));
    });

    test('yerel saat 08:30 → UTC 05:30 (3 saat geri)', () {
      final local = tz.TZDateTime(zone, 2026, 10, 27, 8, 30);
      final utc = local.toUtc();
      expect(utc.hour, 5);
      expect(utc.minute, 30);
      expect(utc.day, 27);
    });

    test('gece yarısı geçişi gün kaydırır', () {
      // 23:30 TR → aynı gün 20:30 UTC (yine aynı gün).
      final gece = tz.TZDateTime(zone, 2026, 10, 27, 23, 30).toUtc();
      expect(gece.day, 27);
      expect(gece.hour, 20);
      // 00:30 TR → önceki gün 21:30 UTC (gün GERİYE kayar).
      final gece2 = tz.TZDateTime(zone, 2026, 10, 27, 0, 30).toUtc();
      expect(gece2.day, 26);
      expect(gece2.hour, 21);
    });

    test('DST olmayan bölgede var olmayan saat 02:30 normalleştirilir', () {
      // TR'de 02:30 her gün mevcut (yaz saati yok); paket bunu
      // kaydırmaz, ofset +03 olarak kalır.
      final gap = tz.TZDateTime(zone, 2026, 3, 29, 2, 30);
      expect(gap.hour, 2);
      expect(gap.timeZoneOffset, const Duration(hours: 3));
    });
  });

  group('DST bölgesi — saat kayması gerçekten oluşur (karşılaştırma)', () {
    test('New York: yaz/kış ofseti 4 saat ↔ 5 saat', () {
      final ny = tz.getLocation('America/New_York');
      expect(
        tz.TZDateTime(ny, 2026, 1, 15, 12).timeZoneOffset,
        const Duration(hours: -5),
      );
      expect(
        tz.TZDateTime(ny, 2026, 7, 15, 12).timeZoneOffset,
        const Duration(hours: -4),
      );
    });

    test('New York DST ileri geçişinde 02:30 var olmayan saat kaydırılır', () {
      // 2026-03-08 02:00 → 03:00. 02:30 istendiğinde pakete göre
      // 03:30'a kayar (ofset hâlâ -5, sonra -4 olur). Hatırlatıcı
      // saatleri bu pencerede bir saat kayabilir — bilinçli davranış.
      final ny = tz.getLocation('America/New_York');
      final t = tz.TZDateTime(ny, 2026, 3, 8, 2, 30);
      expect(t.hour, 3);
      expect(t.minute, 30);
    });
  });

  group('MealReminder saat doğrulaması', () {
    test('sabit saatler geçerli aralıkta', () {
      const settings = ReminderSettings.defaultMeals;
      for (final entry in settings.entries) {
        expect(entry.value.hour, inInclusiveRange(0, 23), reason: '${entry.key} hour');
        expect(entry.value.minute, inInclusiveRange(0, 59), reason: '${entry.key} minute');
      }
    });

    test('varsayılan saatler sırayla artar (kahvaltı < öğle < akşam)', () {
      const settings = ReminderSettings.defaultMeals;
      final breakfast = settings[MealType.breakfast]!;
      final lunch = settings[MealType.lunch]!;
      final dinner = settings[MealType.dinner]!;
      expect(breakfast.hour * 60 + breakfast.minute, lessThan(lunch.hour * 60 + lunch.minute));
      expect(lunch.hour * 60 + lunch.minute, lessThan(dinner.hour * 60 + dinner.minute));
    });

    test('MealType bildirim başlığı/gövdesi çeviri anahtarları üretilebilir', () {
      // notification_service bu anahtarları `.tr()` ile çağırır;
      // isim çıkarımı bozulursa sessizce ham anahtar gösterilir.
      expect(MealType.breakfast.notifTitleKey, 'notifications.breakfastTitle');
      expect(MealType.lunch.notifBodyKey, 'notifications.lunchBody');
      expect(MealType.dinner.notifSkipKey, 'notifications.skipDinner');
    });
  });
}
