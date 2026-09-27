import 'dart:async';

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

  /// Saat dilimi değişiminde hatırlatıcıları yeniden planlamak için
  /// servise bağlanan geri çağrı. `build()` her provider yeniden
  /// oluşturulduğunda yeniden kurulur.
  void Function()? _onTimezoneChanged;

  @override
  ReminderSettings build() {
    ref.onDispose(_disposeTimezoneWatcher);
    if (!kIsWeb) {
      _onTimezoneChanged = () => unawaited(_reschedule());
      NotificationService.instance.addTimezoneWatcher(_onTimezoneChanged!);
    }
    _load();
    return const ReminderSettings();
  }

  void _disposeTimezoneWatcher() {
    final cb = _onTimezoneChanged;
    if (cb == null) return;
    NotificationService.instance.removeTimezoneWatcher(cb);
    _onTimezoneChanged = null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateLegacy(prefs);
    final meals = <MealType, MealReminder>{};
    for (final meal in reminderMeals) {
      final def = ReminderSettings.defaultMeals[meal]!;
      meals[meal] = MealReminder(
        enabled: prefs.getBool(_enabledKey(meal)) ?? false,
        // Bozuk / elle yazılmış kalıcı değerler saat aralığına kırpılır —
        // aksi halde `TZDateTime` 25:00 gibi bir saati ertesi güne
        // normalize edip kullanıcıya yanlış saatte bildirim gönderirdi.
        hour: _clampHour(prefs.getInt(_hourKey(meal)) ?? def.hour, def.hour),
        minute: _clampMinute(
          prefs.getInt(_minuteKey(meal)) ?? def.minute,
          def.minute,
        ),
      );
    }
    state = ReminderSettings(meals: meals);
    await _reschedule();
  }

  /// 0..23 aralığına kırpar, düşerse varsayılana döner.
  static int _clampHour(int value, int fallback) =>
      (value >= 0 && value <= 23) ? value : fallback;

  /// 0..59 aralığına kırpar, düşerse varsayılana döner.
  static int _clampMinute(int value, int fallback) =>
      (value >= 0 && value <= 59) ? value : fallback;

  /// Eski tekil sabah hatırlatıcısını kahvaltı slotuna taşır; kullanıcı
  /// açık/kapalı durumu ve saatiyle kesintisiz devam eder.
  Future<void> _migrateLegacy(SharedPreferences prefs) async {
    if (!prefs.containsKey(_legacyEnabledKey)) return;
    if (!prefs.containsKey(_enabledKey(MealType.breakfast))) {
      final def = ReminderSettings.defaultMeals[MealType.breakfast]!;
      await prefs.setBool(
        _enabledKey(MealType.breakfast),
        prefs.getBool(_legacyEnabledKey) ?? false,
      );
      await prefs.setInt(
        _hourKey(MealType.breakfast),
        _clampHour(prefs.getInt(_legacyHourKey) ?? def.hour, def.hour),
      );
      await prefs.setInt(
        _minuteKey(MealType.breakfast),
        _clampMinute(prefs.getInt(_legacyMinuteKey) ?? def.minute, def.minute),
      );
    }
    await prefs.remove(_legacyEnabledKey);
    await prefs.remove(_legacyHourKey);
    await prefs.remove(_legacyMinuteKey);
  }

  Future<void> setEnabled(MealType meal, bool value) async {
    if (!reminderMeals.contains(meal)) return;
    state = state.copyWith(
      meals: {
        ...state.meals,
        meal: state.meals[meal]!.copyWith(enabled: value),
      },
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey(meal), value);
    await _reschedule();
  }

  /// Saati günceller. Saat/dakika geçersizse yazılmaz — UI'daki
  /// `TimeOfDay` her zaman geçerli olsa da bu sınır ilerideki çağrıları
  /// (migration, içe aktarım) korur.
  Future<void> setTime(MealType meal, int hour, int minute) async {
    if (!reminderMeals.contains(meal)) return;
    final safeHour = _clampHour(hour, ReminderSettings.defaultMeals[meal]!.hour);
    final safeMinute =
        _clampMinute(minute, ReminderSettings.defaultMeals[meal]!.minute);
    state = state.copyWith(
      meals: {
        ...state.meals,
        meal: state.meals[meal]!.copyWith(
          hour: safeHour,
          minute: safeMinute,
        ),
      },
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_hourKey(meal), safeHour);
    await prefs.setInt(_minuteKey(meal), safeMinute);
    await _reschedule();
  }

  Future<void> _reschedule() {
    if (kIsWeb) return Future<void>.value();
    return NotificationService.instance.reschedule(state.meals);
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
        ReminderSettingsNotifier.new);
