import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/notifications/meal_reminder.dart';
import 'package:calorix/core/notifications/reminder_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Öğün bazlı hatırlatıcı ayarları: varsayılanlar, öğün başına kalıcılık ve
/// v1.2.0 tekil "sabah hatırlatıcısı" anahtarlarından göç.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Notifier'ı build() ile başlatır, asenkron _load tamamlanana dek bekler.
  Future<ReminderSettings> loadSettings(ProviderContainer container) async {
    container.read(reminderSettingsProvider.notifier);
    await pumpEventQueue();
    return container.read(reminderSettingsProvider);
  }

  test('varsayılanlar: 3 ana öğün, hepsi kapalı, önerilen saatlerde', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = await loadSettings(container);

    expect(settings.meals.keys, reminderMeals);
    final breakfast = settings.meals[MealType.breakfast]!;
    final lunch = settings.meals[MealType.lunch]!;
    final dinner = settings.meals[MealType.dinner]!;
    expect(breakfast.enabled, isFalse);
    expect(lunch.enabled, isFalse);
    expect(dinner.enabled, isFalse);
    expect((breakfast.hour, breakfast.minute), (8, 30));
    expect((lunch.hour, lunch.minute), (12, 30));
    expect((dinner.hour, dinner.minute), (19, 0));
  });

  test('setEnabled/setTime öğün bazlı kalıcıya yazılır', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(reminderSettingsProvider.notifier);
    await pumpEventQueue();

    await notifier.setEnabled(MealType.lunch, true);
    await notifier.setTime(MealType.dinner, 18, 45);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('reminder_lunch_enabled'), isTrue);
    // dinner'ın enabled'ı hiç değişmedi — anahtar yazılmaz, load null→false.
    expect(prefs.getBool('reminder_dinner_enabled') ?? false, isFalse);
    expect(prefs.getInt('reminder_dinner_hour'), 18);
    expect(prefs.getInt('reminder_dinner_minute'), 45);

    // Yeni provider örneği kalıcı değerlerden ayağa kalkar.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    final reloaded = await loadSettings(second);
    expect(reloaded.meals[MealType.lunch]!.enabled, isTrue);
    expect((reloaded.meals[MealType.dinner]!.hour,
        reloaded.meals[MealType.dinner]!.minute), (18, 45));
    expect(reloaded.meals[MealType.breakfast]!.enabled, isFalse);
  });

  test('göç: tekil sabah hatırlatıcısı kahvaltıya taşınır', () async {
    SharedPreferences.setMockInitialValues({
      'reminder_enabled': true,
      'reminder_hour': 9,
      'reminder_minute': 15,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = await loadSettings(container);

    final breakfast = settings.meals[MealType.breakfast]!;
    expect(breakfast.enabled, isTrue);
    expect((breakfast.hour, breakfast.minute), (9, 15));
    expect(settings.meals[MealType.lunch]!.enabled, isFalse);
    expect(settings.meals[MealType.dinner]!.enabled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('reminder_enabled'), isFalse);
    expect(prefs.containsKey('reminder_hour'), isFalse);
    expect(prefs.containsKey('reminder_minute'), isFalse);
  });

  test('göç: mevcut öğün anahtarı varsa üzerine yazmaz', () async {
    SharedPreferences.setMockInitialValues({
      'reminder_enabled': true,
      'reminder_breakfast_enabled': false,
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = await loadSettings(container);

    expect(settings.meals[MealType.breakfast]!.enabled, isFalse);
  });
}
