import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/notifications/reminder_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `reminder_settings_test.dart` mutlak geçerli değerleri doğruluyor; burada
/// **bozuk kalıcı veri** (elle yazılmış saat, migration, kapsam dışı öğün)
/// davranışı kilitlenir — bunlar sessizce yanlış saatte bildirim üretirdi.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ReminderSettings> load(ProviderContainer c) async {
    c.read(reminderSettingsProvider.notifier);
    await pumpEventQueue();
    return c.read(reminderSettingsProvider);
  }

  test('kalıcı saat aralık dışıysa varsayılana döner', () async {
    // 25 saatlik / 99 dakikalık değerler elle yazılmış ya da bozuk
    // migration kaynaklı olabilir; TZDateTime bunları ertesi güne
    // normalize edip kullanıcıya tamamen farklı bir saatte bildirim
    // gösterirdi.
    SharedPreferences.setMockInitialValues({
      'reminder_lunch_enabled': true,
      'reminder_lunch_hour': 25,
      'reminder_lunch_minute': 99,
      'reminder_dinner_hour': -3,
      'reminder_dinner_minute': 61,
    });

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final settings = await load(c);

    // Varsayılan: lunch 12:30
    expect(settings.meals[MealType.lunch]!.hour, 12);
    expect(settings.meals[MealType.lunch]!.minute, 30);
    // Varsayılan: dinner 19:00
    expect(settings.meals[MealType.dinner]!.hour, 19);
    expect(settings.meals[MealType.dinner]!.minute, 0);
  });

  test('sınır değerleri kabul edilir (0:00 ve 23:59)', () async {
    SharedPreferences.setMockInitialValues({
      'reminder_breakfast_hour': 0,
      'reminder_breakfast_minute': 0,
      'reminder_dinner_hour': 23,
      'reminder_dinner_minute': 59,
    });

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final settings = await load(c);
    expect(settings.meals[MealType.breakfast]!.hour, 0);
    expect(settings.meals[MealType.breakfast]!.minute, 0);
    expect(settings.meals[MealType.dinner]!.hour, 23);
    expect(settings.meals[MealType.dinner]!.minute, 59);
  });

  test('migration bozuk legacy saati varsayılana düşürür', () async {
    // v1.2.0 legacy anahtarları geçersiz saat içeriyor.
    SharedPreferences.setMockInitialValues({
      'reminder_enabled': true,
      'reminder_hour': 99,
      'reminder_minute': -5,
    });

    final c = ProviderContainer();
    addTearDown(c.dispose);
    final settings = await load(c);
    final breakfast = settings.meals[MealType.breakfast]!;
    expect(breakfast.enabled, isTrue);
    expect(breakfast.hour, 8);
    expect(breakfast.minute, 30);
  });

  test('setTime geçersiz değerleri yazmaz, varsayılana sabitler', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(reminderSettingsProvider.notifier);
    await pumpEventQueue();

    await notifier.setTime(MealType.lunch, 30, 120);
    final prefs = await SharedPreferences.getInstance();
    // Yazılan değer geçersiz olsa da kalıcıya geçersiz girmez.
    expect(prefs.getInt('reminder_lunch_hour'), 12);
    expect(prefs.getInt('reminder_lunch_minute'), 30);
    expect(c.read(reminderSettingsProvider).meals[MealType.lunch]!.hour, 12);
  });

  test('setEnabled/setTime kapsam dışı öğünde no-op (assert yerine)', () async {
    // Snack hatırlatıcısı yok; önceki `assert` release'de yoktu, yol
    // `state.meals[meal]!` ile null-assertion crash'i üretiyordu.
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(reminderSettingsProvider.notifier);
    await pumpEventQueue();

    await notifier.setEnabled(MealType.snack, true);
    await notifier.setTime(MealType.snack, 10, 10);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('reminder_snack_enabled'), isFalse);
    expect(prefs.containsKey('reminder_snack_hour'), isFalse);
  });

  test('saat dilimi geri çağrısı provider iptalinde kaldırılır', () async {
    // Notifier, saat dilimi değişiminde yeniden planlama yapmak için
    // servise bir geri çağrı bağlar; dispose olmadan bağlı kalırsa
    // kaldırılmış provider tetiklenir.
    final c = ProviderContainer();
    c.read(reminderSettingsProvider.notifier);
    await pumpEventQueue();
    c.dispose();

    // Yeniden bağlanan ikinci container sorunsuz kurulur.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    await load(second);
  });
}
