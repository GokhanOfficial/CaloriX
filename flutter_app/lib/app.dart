import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/web_reminder.dart';
import 'core/observability/sentry_user_context.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/updates/update_gate.dart';

class CalorixApp extends ConsumerStatefulWidget {
  const CalorixApp({super.key});

  @override
  ConsumerState<CalorixApp> createState() => _CalorixAppState();
}

class _CalorixAppState extends ConsumerState<CalorixApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  WebReminder? _webReminder;

  /// Bildirim aksiyonu aboneliği — `dispose`'da kapatılır (sızıntı yok).
  StreamSubscription<String>? _actionSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webReminder = WebReminder(ref, _messengerKey)..start();
    } else {
      unawaited(_initNotifications());
    }
  }

  Future<void> _initNotifications() async {
    final service = NotificationService.instance;
    await service.init();
    if (!mounted) return;
    await _actionSub?.cancel();
    _actionSub = service.onAction.listen(_handleAction);
  }

  void _handleAction(String action) {
    if (action.startsWith('${NotificationService.actionSnooze}:')) {
      final meal =
          MealType.values.asNameMap()[action.split(':').last];
      if (meal != null) NotificationService.instance.snoozeOneHour(meal);
      return;
    }
    switch (action) {
      case NotificationService.actionOpen:
        ref.read(appRouterProvider).go(AppRoutes.dashboard);
        break;
      // action_skip: bildirim zaten kapandı, ek işlem yok.
    }
  }

  @override
  void dispose() {
    unawaited(_actionSub?.cancel());
    _actionSub = null;
    _webReminder?.dispose();
    NotificationService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    // Oturum değişiminde Sentry kullanıcı bağlamını günceller (sadece UUID).
    ref.watch(sentryUserContextProvider);
    final themeNotifier = ref.watch(themeModeProvider.notifier);
    // state değişimini dinlemek için:
    ref.watch(themeModeProvider);

    return ScaffoldMessenger(
      key: _messengerKey,
      child: MaterialApp.router(
        title: 'CaloriX',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeNotifier.materialThemeMode,
        routerConfig: router,
        builder: (context, child) =>
            UpdateGate(child: child ?? const SizedBox.shrink()),
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
      ),
    );
  }
}
