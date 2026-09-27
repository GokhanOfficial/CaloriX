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

  /// Web'de "1 saat ertele" gerçekten erteleme yapmalı: gösterim [MealType]
  /// için günlük `_shown` işareti **kaldırılır** ve tekrar denenecek saat
  /// [_retryAt] içine yazılır. Önceki kod `_shown`'a önce eklediği için
  /// buton hiçbir etki göstermiyordu (sessiz ölü özellik).
  final Map<MealType, DateTime> _retryAt = {};

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _shown.clear();
    _snoozedUntil.clear();
    _retryAt.clear();
  }

  void _check() {
    final settings = _ref.read(reminderSettingsProvider);
    final now = DateTime.now();
    final today = _dayKey(now);

    // Bellek sınırı: yalnızca bugünün anahtarları tutulur.
    _shown.removeWhere((key) => !key.startsWith('$today|'));
    // Süresi dolmuş erteleme/tekrar deneme kayıtları temizlenir.
    _retryAt.removeWhere((_, at) => !now.isBefore(at));
    _snoozedUntil.removeWhere((_, at) => !now.isBefore(at));

    for (final meal in reminderMeals) {
      final reminder = settings.meals[meal];
      if (reminder == null || !reminder.enabled) continue;
      if (_shown.contains('$today|${meal.name}')) continue;

      // "1 saat ertele": tekrar deneme saati gelene kadar bekle.
      final retryAt = _retryAt[meal];
      if (retryAt != null && now.isBefore(retryAt)) continue;

      final target = DateTime(
          now.year, now.month, now.day, reminder.hour, reminder.minute);
      if (now.isBefore(target)) continue;

      _shown.add('$today|${meal.name}');
      _show(meal);
    }
  }

  /// Gün anahtarı — `widget_snapshot.dart`'taki `formatEntryDate` ile aynı
  /// `yyyy-MM-dd` biçimini (sıfır dolgulu) üretir.
  static String _dayKey(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
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
              final now = DateTime.now();
              _snoozedUntil[meal] = now.add(const Duration(hours: 1));
              _retryAt[meal] = _snoozedUntil[meal]!;
              // Günlük işareti kaldırılır ki 1 saat sonra tekrar gösterilsin.
              _shown.remove('${_dayKey(now)}|${meal.name}');
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
