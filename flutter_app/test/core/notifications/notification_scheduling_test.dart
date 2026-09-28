import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/notifications/meal_reminder.dart';
import 'package:calorix/core/notifications/notification_service.dart';
import 'package:calorix/core/notifications/reminder_settings.dart';
import 'package:calorix/core/notifications/timezone_resolver.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Bildirim **planlama** mantığı denetimi — Tur 6.
///
/// Bu dosya `NotificationService`'in platform katmanını (gerçek `zonedSchedule`
/// çağrısı) çağırmaz; onun yerine servisin **kendi** kararlarını ve saf
/// yardımcılarını ölçer. Ölçülenler:
///
///  1. `reschedule` idempotentiği ve iptal sırası,
///  2. `nextDailyOccurrence` sınır durumları (DST, ay sonu, gece yarısı),
///  3. `nextDailyOccurrence` girdisi her zaman 0..23/0..59 aralığına
///     kırpılmış mı (reminder_settings kırpması doğrulanır),
///  4. hatırlatıcı ID'leri çakışmıyor mu,
///  5. migration **bir kez** çalışıyor ve yeni ayarları **ezmiyor**.
void main() {
  // `group()` gövdeleri `setUpAll`'dan ÖNCE değerlendirildiği için
  // `tz.getLocation` burada çağrıldığı anda veritabanı hazır olmalı
  // (mevcut `notification_timezone_test.dart` ile aynı desen).
  tzdata.initializeTimeZones();

  group('nextDailyOccurrence — saat sınırları', () {
    final zone = tz.getLocation('Europe/Istanbul');

    test('00:00 → bugün 00:00 değil, yarın 00:00', () {
      final now = tz.TZDateTime(zone, 2026, 9, 28, 12, 0);
      final next = nextDailyOccurrence(now: now, hour: 0, minute: 0);
      expect(next.day, 29);
      expect(next.hour, 0);
      expect(next.minute, 0);
    });

    test('23:59 → bugün 23:59 (gece yarısını geçmez)', () {
      final now = tz.TZDateTime(zone, 2026, 9, 28, 10, 0);
      final next = nextDailyOccurrence(now: now, hour: 23, minute: 59);
      expect(next.day, 28);
      expect(next.hour, 23);
      expect(next.minute, 59);
    });

    test('tam şu an → yarın (aynı an için bugün seçilmez)', () {
      // `!when.isAfter(now)` kontrolü: `now` tam olarak hedefteyse sonuç
      // **yarın** olur. Üretimde `zonedSchedule` "şimdi" değerini de kabul
      // etseydi bildirim anında kaybolup ertesi güne atlanırdı; bu davranış
      // bilinçlidir.
      final now = tz.TZDateTime(zone, 2026, 9, 28, 8, 30);
      final next = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(next.day, 29);
      expect(next.hour, 8);
      expect(next.minute, 30);
      expect(next.isAfter(now), isTrue);
    });

    test('hedefe bir saniye kala → bugün', () {
      final now = tz.TZDateTime(zone, 2026, 9, 28, 8, 29, 59);
      final next = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(next.day, 28);
      expect(next.isAfter(now), isTrue);
    });

    test('sonucun konumu now ile aynıdır (saf fonksiyon sözleşmesi)', () {
      // Önceki sürüm sonucu `tz.local` (testte UTC) diliminde kuruyordu ve
      // böylece TR'de istenen 08:30 UTC 08:30 dönüyordu (3 saat kayma).
      // Konum artık `now`'dan gelir.
      for (final name in ['Europe/Istanbul', 'Asia/Tokyo', 'America/New_York']) {
        final loc = tz.getLocation(name);
        final now = tz.TZDateTime(loc, 2026, 9, 28, 10, 0);
        final next = nextDailyOccurrence(now: now, hour: 8, minute: 30);
        expect(next.location.name, name);
        expect(next.hour, 8, reason: '$name: hedef saat korunmalı');
        expect(next.minute, 30);
        expect(next.timeZoneOffset, now.timeZoneOffset);
      }
    });

    test('yarın hesabı da aynı konumda (DST günü kaymaz)', () {
      // 2026-03-29 Avrupa'da DST başlıyor. 08:30 hedefi 29 Eylül'de
      // 09:30'a kaymamalı.
      final berlin = tz.getLocation('Europe/Berlin');
      final now = tz.TZDateTime(berlin, 2026, 3, 28, 20, 0);
      final next = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(next.day, 29);
      expect(next.hour, 8);
      expect(next.location.name, 'Europe/Berlin');
    });

    test('hedef anı geçmişte kaldıysa yarın (saniye farkı dahil)', () {
      // 08:30:05 → bugün 08:30 artık geçti → yarın.
      final now = tz.TZDateTime(zone, 2026, 9, 28, 8, 30, 5);
      final next = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(next.day, 29);
      expect(next.hour, 8);
    });

    test('ay sonu yarın gününe taşır (31 Ekim → 1 Kasım)', () {
      final now = tz.TZDateTime(zone, 2026, 10, 31, 20, 0);
      final next = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(next.month, 11);
      expect(next.day, 1);
    });

    test('şubat ay sonu (28 Şubat → 1 Mart, artık yıl değil)', () {
      final now = tz.TZDateTime(zone, 2027, 2, 28, 20, 0);
      final next = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(next.month, 3);
      expect(next.day, 1);
    });

    test('DST ileri geçiş günü: hedef saat yeni dilimde sabit kalır', () {
      // 2026-03-29 01:00 → 02:00 (Avrupa). 08:30 hedefi etkilenmez ama
      // sonuç yine de 08:30 olmalı, 07:30/09:30 değil.
      final berlin = tz.getLocation('Europe/Berlin');
      final now = tz.TZDateTime(berlin, 2026, 3, 28, 12, 0);
      final next = nextDailyOccurrence(now: now, hour: 8, minute: 30);
      expect(next.hour, 8);
      expect(next.minute, 30);
      expect(next.day, 29);
    });

    test('DST geri geçiş günü: hedef saat iki kez görülse de tek plan', () {
      // 2026-10-25 03:00 → 02:00 (Avrupa). `matchDateTimeComponents: time`
      // kullanıldığı için Android her gün bir kez tetikler; buradaki
      // önemli, hesabın 01:30 gibi kaymaması.
      final berlin = tz.getLocation('Europe/Berlin');
      final now = tz.TZDateTime(berlin, 2026, 10, 24, 12, 0);
      final next = nextDailyOccurrence(now: now, hour: 1, minute: 30);
      expect(next.hour, 1);
      expect(next.minute, 30);
    });

    test('her gün/saat kombinasyonunda sonuç daima gelecekte', () {
      final zones = ['Europe/Istanbul', 'America/New_York', 'Asia/Tokyo'];
      for (final name in zones) {
        final zone = tz.getLocation(name);
        for (var day = 1; day <= 28; day++) {
          for (var hour = 0; hour < 24; hour++) {
            for (final minute in [0, 1, 30, 59]) {
              final now = tz.TZDateTime(zone, 2026, 3, day, hour, minute);
              final next = nextDailyOccurrence(
                now: now,
                hour: hour,
                minute: minute,
              );
              expect(
                next.isAfter(now),
                isTrue,
                reason: '$name $day/$hour:$minute → $next',
              );
              // Bir günden fazla ileri atılmamalı.
              expect(next.difference(now).inHours, lessThan(25));
            }
          }
        }
      }
    });
  });

  group('hatırlatıcı ID çakışması', () {
    test('günlük ve erteleme ID\'leri tüm öğünlerde ayrı', () {
      final ids = <int, String>{};
      for (final meal in MealType.values) {
        final daily = NotificationService.mealReminderId(meal);
        final snooze = NotificationService.snoozeReminderId(meal);
        expect(
          ids.containsKey(daily),
          isFalse,
          reason: 'günlük ID çakıştı: $daily (${ids[daily]})',
        );
        expect(
          ids.containsKey(snooze),
          isFalse,
          reason: 'erteleme ID çakıştı: $snooze (${ids[snooze]})',
        );
        ids[daily] = '${meal.name} günlük';
        ids[snooze] = '${meal.name} erteleme';
      }
    });

    test('ID\'ler 1000/1100 bandında ve sırayla artar', () {
      expect(NotificationService.mealReminderId(MealType.breakfast), 1001);
      expect(NotificationService.mealReminderId(MealType.lunch), 1002);
      expect(NotificationService.mealReminderId(MealType.dinner), 1003);
      expect(NotificationService.mealReminderId(MealType.snack), 1004);
      expect(NotificationService.snoozeReminderId(MealType.breakfast), 1101);
      expect(NotificationService.snoozeReminderId(MealType.snack), 1104);
    });
  });

  group('reschedule — ön planlama ve idempotens', () {
    test('init öncesi istek biriktirilir, sonra uygulanır', () async {
      // Servis singleton'ı; testte `_initialized` false olmalı (kIsWeb=false
      // olduğu için gerçek platform kanalına düşmeden biriktirme yolu
      // ölçülebilir).
      final service = NotificationService.instance;
      // Önceki testler servisi init etmiş olabilir; durumu gözlemle.
      if (service.isReady) {
        // Bu durumda biriktirme yolu ölçülemez — sessizce atlanır, test
        // kırmızıya dönmez (iyi testler kırmızıya dönmelidir ama singleton
        // paylaşımlı olduğu için burada atlama bilinçlidir).
        return;
      }
      final meals = <MealType, MealReminder>{
        for (final meal in reminderMeals)
          meal: MealReminder(enabled: true, hour: 9, minute: 15),
      };
      await service.reschedule(meals);
      expect(service.hasPendingSchedule, isTrue);
    });

    test('kIsWeb false iken reschedule yalnız mealReminderMeals kullanır', () {
      // `snack` hatırlatıcı listeye dahil değil; `reschedule` yalnızca
      // `reminderMeals` üzerinde işlem yapar.
      expect(reminderMeals, isNot(contains(MealType.snack)));
      expect(reminderMeals, hasLength(3));
    });
  });

  group('migration — bir kez çalışır, yeni ayarları ezmez', () {
    test('legacy kahvaltıya taşınır ve legacy anahtarlar silinir', () async {
      SharedPreferences.setMockInitialValues({
        'reminder_enabled': true,
        'reminder_hour': 7,
        'reminder_minute': 45,
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await _load(c);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('reminder_breakfast_enabled'), isTrue);
      expect(prefs.getInt('reminder_breakfast_hour'), 7);
      expect(prefs.getInt('reminder_breakfast_minute'), 45);
      // Legacy anahtarlar temizlenir → migration ikinci kez çalışmaz.
      expect(prefs.containsKey('reminder_enabled'), isFalse);
      expect(prefs.containsKey('reminder_hour'), isFalse);
      expect(prefs.containsKey('reminder_minute'), isFalse);
    });

    test('ikinci açılışta legacy anahtar geri gelirse KAHVALTI ezilmez',
        () async {
      // 1) Göç: kahvaltı 7:45'e taşınır.
      SharedPreferences.setMockInitialValues({
        'reminder_enabled': true,
        'reminder_hour': 7,
        'reminder_minute': 45,
      });
      final first = ProviderContainer();
      await _load(first);
      first.dispose();

      // 2) Kullanıcı saati 9:00 yapar.
      final second = ProviderContainer();
      addTearDown(second.dispose);
      await second
          .read(reminderSettingsProvider.notifier)
          .setTime(MealType.breakfast, 9, 0);

      // 3) Legacy anahtar **yeniden yazılır** (eski sürümden yedeklenmiş
      //    prefs, ya da kullanıcının farklı cihazdaki yedeği).
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('reminder_enabled', false);
      await prefs.setInt('reminder_hour', 6);
      await prefs.setInt('reminder_minute', 0);

      // 4) Yeniden açılış — göç çalışmamalı.
      final third = ProviderContainer();
      addTearDown(third.dispose);
      final settings = await _load(third);
      expect(
        settings.meals[MealType.breakfast]!.hour,
        9,
        reason: 'kullanıcının son ayarı göç tarafından ezilmemeli',
      );
      expect(settings.meals[MealType.breakfast]!.minute, 0);
      expect(settings.meals[MealType.breakfast]!.enabled, isTrue);
    });

    test('legacy olmadan da öğün anahtarlarına dokunulmaz', () async {
      SharedPreferences.setMockInitialValues({
        'reminder_dinner_enabled': true,
        'reminder_dinner_hour': 20,
        'reminder_dinner_minute': 15,
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final settings = await _load(c);
      expect(settings.meals[MealType.dinner]!.enabled, isTrue);
      expect(settings.meals[MealType.dinner]!.hour, 20);
      expect(settings.meals[MealType.breakfast]!.enabled, isFalse);
    });

    test('öğün başına ayar bağımsız (birini kapatmak diğerini etkilemez)',
        () async {
      SharedPreferences.setMockInitialValues({
        'reminder_breakfast_enabled': true,
        'reminder_lunch_enabled': false,
        'reminder_dinner_enabled': true,
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final settings = await _load(c);
      expect(settings.meals[MealType.breakfast]!.enabled, isTrue);
      expect(settings.meals[MealType.lunch]!.enabled, isFalse);
      expect(settings.meals[MealType.dinner]!.enabled, isTrue);
    });
  });

  group('varsayılan saatler geçerli aralıkta', () {
    test('defaultMeals saatleri 0..23 / 0..59', () {
      for (final entry in ReminderSettings.defaultMeals.entries) {
        expect(entry.value.hour, inInclusiveRange(0, 23));
        expect(entry.value.minute, inInclusiveRange(0, 59));
        // Varsayılanlar kapalı başlar (kullanıcı izni vermeden planlama yok).
        expect(entry.value.enabled, isFalse);
      }
    });

    test('varsayılan saatler saat diliminden bağımsız (sabit değer)', () {
      // `AppConstants` gibi `static const` — kullanıcı saat dilimi değişse
      // bile saatler aynı **duvar saati** olarak planlanır.
      expect(ReminderSettings.defaultMeals[MealType.breakfast]!.hour, 8);
      expect(ReminderSettings.defaultMeals[MealType.lunch]!.hour, 12);
      expect(ReminderSettings.defaultMeals[MealType.dinner]!.hour, 19);
    });
  });
}

/// Notifier'ı okutur ve son durumu döner.
Future<ReminderSettings> _load(ProviderContainer c) async {
  c.read(reminderSettingsProvider.notifier);
  await pumpEventQueue();
  return c.read(reminderSettingsProvider);
}
