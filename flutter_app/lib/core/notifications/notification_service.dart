import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Günlük kalori hatırlatıcı bildirimlerini yöneten servis (Android).
///
/// Web'de tüm çağrılar no-op'tur; web tarafında uygulama içi hatırlatma
/// [WebReminder] ile yapılır. iOS hedeflenirse init'e DarwinInitialization
/// eklenerek aynı API kullanılabilir.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const int dailyReminderId = 1001;
  static const int snoozeReminderId = 1002;
  static const String channelId = 'daily_reminders';
  static const String actionSkip = 'action_skip';
  static const String actionSnooze = 'action_snooze';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Bildirim aksiyonları ("Kahvaltı yapmayacağım", "1 saat ertele").
  final StreamController<String> _actions = StreamController.broadcast();
  Stream<String> get onAction => _actions.stream;

  bool _initialized = false;
  bool get isReady => _initialized;

  /// Android 12+ exact alarm izni yoksa inexact planlamaya düşer.
  bool _exactAllowed = true;

  Future<void> init() async {
    if (kIsWeb || _initialized) return;
    try {
      tzdata.initializeTimeZones();
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      // timezone alınamazsa UTC fallback ile devam edilir.
    }

    const androidInit = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    try {
      await _plugin.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
    } catch (_) {
      return;
    }

    await _ensurePermission();
    _initialized = true;
  }

  Future<void> _ensurePermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.requestNotificationsPermission();
    _exactAllowed = await android.requestExactAlarmsPermission() ?? true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId == actionSkip || response.actionId == actionSnooze) {
      _actions.add(response.actionId!);
    } else if (response.id == dailyReminderId ||
        response.id == snoozeReminderId) {
      // Gövdeye tıklama — aksiyon yok, sadece akış.
      _actions.add('action_open');
    }
  }

  /// Günlük hatırlatıcıyı (yeniden) planlar; kapalıysa iptal eder.
  Future<void> reschedule({required bool enabled, int hour = 8, int minute = 30}) async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(dailyReminderId);
    await _plugin.cancel(snoozeReminderId);
    if (!enabled) return;

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      dailyReminderId,
      'notif.breakfastTitle'.tr(),
      'notif.breakfastBody'.tr(),
      when,
      _details(),
      androidScheduleMode: _exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'daily_reminder',
    );
  }

  /// "1 saat ertele" — günlük plan korunur, ek olarak 1 saat sonra tek seferlik
  /// hatırlatma gösterir.
  Future<void> snoozeOneHour() async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(snoozeReminderId);
    await _plugin.zonedSchedule(
      snoozeReminderId,
      'notif.breakfastTitle'.tr(),
      'notif.breakfastBody'.tr(),
      tz.TZDateTime.now(tz.local).add(const Duration(hours: 1)),
      _details(showActions: false),
      androidScheduleMode: _exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'snooze_reminder',
    );
  }

  NotificationDetails _details({bool showActions = true}) {
    final actions = showActions
        ? [
            AndroidNotificationAction(
              actionSnooze,
              'notif.snoozeHour'.tr(),
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              actionSkip,
              'notif.skipBreakfast'.tr(),
              showsUserInterface: false,
            ),
          ]
        : null;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Günlük hatırlatıcılar',
        channelDescription: 'Sabah kalori / öğün hatırlatmaları',
        importance: Importance.high,
        priority: Priority.high,
        color: const Color(0xFF00C7B7),
        actions: actions,
      ),
    );
  }

  void dispose() => _actions.close();
}
