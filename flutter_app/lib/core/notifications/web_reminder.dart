import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'reminder_settings.dart';

/// Web fallback: `flutter_local_notifications` web desteklemediğinden,
/// uygulama açıkken periyodik Timer ile hatırlatma banner'ı gösterir.
/// Aynı gün için yalnızca bir kez tetiklenir; erteleme 1 saat sonraya alır.
class WebReminder {
  WebReminder(this._ref, this._messengerKey);

  final WidgetRef _ref;
  final GlobalKey<ScaffoldMessengerState> _messengerKey;
  Timer? _timer;
  DateTime? _lastShownDay;
  DateTime? _snoozedUntil;

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
    if (!settings.enabled) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_lastShownDay == today) return;
    if (_snoozedUntil != null && now.isBefore(_snoozedUntil!)) return;

    final target = DateTime(
        now.year, now.month, now.day, settings.hour, settings.minute);
    if (now.isBefore(target)) return;

    _lastShownDay = today;
    _show();
  }

  void _show() {
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: Text('notif.breakfastBody'.tr()),
        leading: const Icon(Icons.notifications_active_outlined),
        actions: [
          TextButton(
            onPressed: () {
              _snoozedUntil = DateTime.now().add(const Duration(hours: 1));
              messenger.hideCurrentMaterialBanner();
            },
            child: Text('notif.snoozeHour'.tr()),
          ),
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text('notif.skipBreakfast'.tr()),
          ),
        ],
      ),
    );
  }
}
