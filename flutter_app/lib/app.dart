import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/web_reminder.dart';
import 'core/observability/app_logger.dart';
import 'core/observability/sentry_user_context.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/updates/update_gate.dart';
import 'core/widgets/widget_bridge.dart';
import 'features/settings/widgets/widget_settings_dialog.dart';

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

  /// Widget deep link aboneliği — `dispose`'da kapatılır.
  StreamSubscription<Uri?>? _linkSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webReminder = WebReminder(ref, _messengerKey)..start();
    } else {
      unawaited(_initNotifications());
      unawaited(_initDeepLinks());
    }
  }

  /// Ana ekran widget'ından gelen deep link'leri dinler.
  ///
  /// Widget'ın ayarlar düğmesi `calorix://widget/settings` açar. Uygulama
  /// çalışırken gelen link anında, kapalıyken gelen link ise açılıştan sonra
  /// ele alınır (ilk değer de okunur, aksi halde soğuk başlangıçta kaybolur).
  Future<void> _initDeepLinks() async {
    try {
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initial != null) _handleDeepLink(initial);
      _linkSub ??= HomeWidget.widgetClicked.listen(_handleDeepLink);
    } catch (e, s) {
      AppLog.w('Deep link dinleyicisi kurulamadı', e, s);
    }
  }

  void _handleDeepLink(Uri? uri) {
    if (uri == null) return;
    if (uri.toString() == DeepLinks.widgetSettings ||
        uri.path == '/settings' ||
        uri.host == 'widget') {
      // Router hazır olmadan `go` çağırmak no-op olur; post-frame'e alınır.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(WidgetSettingsDialog.openFromDeepLink(ref));
      });
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
    unawaited(_linkSub?.cancel());
    _linkSub = null;
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
        builder: (context, child) => WidgetBridgeScope(
          // WidgetBridgeScope, UpdateGate'in altına sarılır: hem zorunlu
          // güncelleme ekranında hem de normal akışta günlük veri yayını yapılır
          // (böylece kullanıcı güncelleme sonrası widget'ında güncel veri görür).
          child: UpdateGate(child: child ?? const SizedBox.shrink()),
        ),
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
      ),
    );
  }
}
