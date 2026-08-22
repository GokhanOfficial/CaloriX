import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'meal_reminder.dart';
import 'notification_service.dart';

/// Öğün hatırlatıcı ayarları — cihaza lokal (SharedPreferences),
/// bildirim zamanlayıcısıyla doğrudan uyumlu. Supabase'e yazılmaz.
class ReminderSettings {
  const ReminderSettings({Map<MealType, MealReminder>? meals})
      : meals = meals ?? defaultMeals;

  /// Öğün başına varsayılan saatler — hepsi kapalı başlar.
  static const Map<MealType, MealReminder> defaultMeals = {
    MealType.breakfast: MealReminder(hour: 8, minute: 30),
    MealType.lunch: MealReminder(hour: 12, minute: 30),
    MealType.dinner: MealReminder(hour: 19, minute: 0),
  };

  final Map<MealType, MealReminder> meals;

  ReminderSettings copyWith({Map<MealType, MealReminder>? meals}) =>
      ReminderSettings(meals: meals ?? this.meals);
}

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  // v1.2.0'daki tekil "sabah hatırlatıcısı" anahtarları — göç için.
  static const _legacyEnabledKey = 'reminder_enabled';
  static const _legacyHourKey = 'reminder_hour';
  static const _legacyMinuteKey = 'reminder_minute';

  static String _enabledKey(MealType meal) => 'reminder_${meal.name}_enabled';
  static String _hourKey(MealType meal) => 'reminder_${meal.name}_hour';
  static String _minuteKey(MealType meal) => 'reminder_${meal.name}_minute';

  @override
  ReminderSettings build() {
    _load();
    return const ReminderSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);
    final meals = <MealType, MealReminder>{};
    for (final meal in reminderMeals) {
      final def = ReminderSettings.defaultMeals[meal]!;
      meals[meal] = MealReminder(
        enabled: prefs.getBool(_enabledKey(meal)) ?? false,
        hour: prefs.getInt(_hourKey(meal)) ?? def.hour,
        minute: prefs.getInt(_minuteKey(meal)) ?? def.minute,
      );
    }
    state = ReminderSettings(meals: meals);
    await _reschedule();
  }

  /// Eski tekil sabah hatırlatıcısını kahvaltı slotuna taşır; kullanıcı
  /// açık/kapalı durumu ve saatiyle kesintisiz devam eder.
  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    if (!prefs.containsKey(_legacyEnabledKey)) return;
    if (!prefs.containsKey(_enabledKey(MealType.breakfast))) {
      await prefs.setBool(_enabledKey(MealType.breakfast),
          prefs.getBool(_legacyEnabledKey) ?? false);
      await prefs.setInt(
          _hourKey(MealType.breakfast), prefs.getInt(_legacyHourKey) ?? 8);
      await prefs.setInt(_minuteKey(MealType.breakfast),
          prefs.getInt(_legacyMinuteKey) ?? 30);
    }
    await prefs.remove(_legacyEnabledKey);
    await prefs.remove(_legacyHourKey);
    await prefs.remove(_legacyMinuteKey);
  }

  Future<void> setEnabled(MealType meal, bool value) async {
    assert(reminderMeals.contains(meal), '$meal için hatırlatıcı desteklenmiyor');
    state = state.copyWith(
      meals: {...state.meals, meal: state.meals[meal]!.copyWith(enabled: value)},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey(meal), value);
    await _reschedule();
  }

  Future<void> setTime(MealType meal, int hour, int minute) async {
    assert(reminderMeals.contains(meal), '$meal için hatırlatıcı desteklenmiyor');
    state = state.copyWith(
      meals: {...state.meals, meal: state.meals[meal]!.copyWith(hour: hour, minute: minute)},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey(meal), hour);
    await prefs.setInt(_minuteKey(meal), minute);
    await _reschedule();
  }

  Future<void> _reschedule() async {
    if (kIsWeb) return;
    await NotificationService.instance.reschedule(state.meals);
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
        ReminderSettingsNotifier.new);
