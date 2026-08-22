import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Sabah kalori hatırlatıcısı ayarları — cihaza lokal (SharedPreferences),
/// bildirim zamanlayıcısıyla doğrudan uyumlu. Supabase'e yazılmaz.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.hour = 8,
    this.minute = 30,
  });

  final bool enabled;
  final int hour;
  final int minute;

  ReminderSettings copyWith({bool? enabled, int? hour, int? minute}) =>
      ReminderSettings(
        enabled: enabled ?? this.enabled,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );
}

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  static const enabledKey = 'reminder_enabled';
  static const hourKey = 'reminder_hour';
  static const minuteKey = 'reminder_minute';

  @override
  ReminderSettings build() {
    _load();
    return const ReminderSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReminderSettings(
      enabled: prefs.getBool(enabledKey) ?? false,
      hour: prefs.getInt(hourKey) ?? 8,
      minute: prefs.getInt(minuteKey) ?? 30,
    );
    await _reschedule();
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
    await _reschedule();
  }

  Future<void> setTime(int hour, int minute) async {
    state = state.copyWith(hour: hour, minute: minute);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(hourKey, hour);
    await prefs.setInt(minuteKey, minute);
    await _reschedule();
  }

  Future<void> _reschedule() async {
    if (kIsWeb) return;
    await NotificationService.instance.reschedule(
      enabled: state.enabled,
      hour: state.hour,
      minute: state.minute,
    );
  }
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(
        ReminderSettingsNotifier.new);
