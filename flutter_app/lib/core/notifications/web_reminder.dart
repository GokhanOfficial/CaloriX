import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import 'meal_reminder.dart';
import 'reminder_settings.dart';

/// Web fallback: `flutter_local_notifications` web desteklemediğinden,
/// uygulama açıkken periyodik Timer ile hatırlatma banner'ı gösterir.
/// Öğün başına günde bir kez tetiklenir; erteleme 1 saat sonraya alır.
class WebReminder {
  WebReminder(this._ref, this._messengerKey);

  final WidgetRef _ref;
  final GlobalKey<ScaffoldMessengerState> _messengerKey;
  Timer? _timer;

  /// "gün|öğün" anahtarları — o gün gösterilen öğün hatırlatmaları.
  final Set<String> _shown = {};
  final Map<MealType, DateTime> _snoozedUntil = {};

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  void _check() {
    final settings = _ref.read(reminderSettingsProvider);
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    _shown.removeWhere((key) => !key.startsWith('$today|'));

    for (final meal in reminderMeals) {
      final reminder = settings.meals[meal];
      if (reminder == null || !reminder.enabled) continue;
      if (_shown.contains('$today|${meal.name}')) continue;
      final snoozedUntil = _snoozedUntil[meal];
      if (snoozedUntil != null && now.isBefore(snoozedUntil)) continue;

      final target = DateTime(
          now.year, now.month, now.day, reminder.hour, reminder.minute);
      if (now.isBefore(target)) continue;

      _shown.add('$today|${meal.name}');
      _show(meal);
    }
  }

  void _show(MealType meal) {
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text(meal.notifBodyKey.tr()),
        leading: const Icon(Icons.notifications_active_outlined),
        actions: [
          TextButton(
            onPressed: () {
              _snoozedUntil[meal] =
                  DateTime.now().add(const Duration(hours: 1));
              messenger.hideCurrentMaterialBanner();
            },
            child: Text('notifications.snoozeHour'.tr()),
          ),
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text(meal.notifSkipKey.tr()),
          ),
        ],
      ),
    );
  }
}
