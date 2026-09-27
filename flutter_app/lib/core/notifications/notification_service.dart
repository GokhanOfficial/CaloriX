import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';
import '../observability/app_logger.dart';
import 'meal_reminder.dart';
import 'timezone_resolver.dart';

export 'timezone_resolver.dart' show resolveTimeZone;

/// Öğün hatırlatıcı bildirimlerini yöneten servis (Android).
///
/// Web'de tüm çağrılar no-op'tur; web tarafında uygulama içi hatırlatma
/// [WebReminder] ile yapılır. iOS hedeflenirse init'e DarwinInitialization
/// eklenerek aynı API kullanılabilir.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Öğün bildirim ID'leri: 1000 + sıra (1001 kahvaltı, 1002 öğle, 1003 akşam).
  static int mealReminderId(MealType meal) => 1000 + meal.order;

  /// Erteleme bildirim ID'leri: 1100 + sıra (öğün bildirimleriyle çakışmaz).
  static int snoozeReminderId(MealType meal) => 1100 + meal.order;

  static const String channelId = 'daily_reminders';
  static const String actionSkip = 'action_skip';
  static const String actionSnooze = 'action_snooze';
  static const String actionOpen = 'action_open';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Bildirim aksiyonları ("1 saat ertele", "öğünü atla"). Aksiyon kimliği
  /// `action_snooze:lunch` biçiminde öğün bilgisi taşır.
  final StreamController<String> _actions = StreamController.broadcast();
  Stream<String> get onAction => _actions.stream;

  bool _initialized = false;
  bool get isReady => _initialized;

  /// Uygulama ön planlaması — `init()` tamamlanmadan önce gelen
  /// [reschedule] istekleri biriktirilir ve `init` sonunda uygulanır.
  ///
  /// Önceki davranış `!_initialized` koşulunda isteği sessizce düşürüyordu.
  /// `ReminderSettingsNotifier.build()` uygulama açılışında, `app.dart`'deki
  /// asenkron `_initNotifications()`'tan **önce** çalıştığı için kalıcı
  /// hatırlatıcı ayarları ilk açılışta hiç planlanmıyordu; kullanıcı ancak
  /// ayarlardan bir kere dokunduğunda hatırlatıcılar çalışıyordu.
  Map<MealType, MealReminder>? _pendingSchedule;

  /// Son uygulanan yerel saat dilimi adı — cihaz dilimi değiştiğinde
  /// hatırlatıcıların yeniden planlanması için saklanır.
  String? _tzName;

  /// Başarıyla çözülen cihaz saat dilimi (`null` = UTC'ye düşüldü).
  String? get localTimeZoneName => _tzName;

  /// Saat dilimi değiştiğinde çağrılacak geri çağrılar. Uygulama ön planı
  /// (arkada reschedule) tarafından doldurulur.
  final List<void Function()> _timezoneWatchers = [];

  /// `tz` veritabanı başlatıldı mı — `reschedule` erken çağrıldığında
  /// `tz.local`'in UTC olmasını önler.
  bool _tzReady = false;

  /// Android 12+ exact alarm izni yoksa inexact planlamaya düşer.
  bool _exactAllowed = true;

  Future<void> init() async {
    if (kIsWeb || _initialized) return;
    tzdata.initializeTimeZones();
    _tzReady = true;
    await applyLocalTimeZone();

    const androidInit = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    try {
      await _plugin.initialize(
        const InitializationSettings(android: androidInit),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
    } catch (e, s) {
      AppLog.e('Bildirim plugini başlatılamadı', e, s);
      return;
    }

    await _ensurePermission();
    _initialized = true;

    // init öncesinde gelen planlama isteğini şimdi uygula.
    final pending = _pendingSchedule;
    _pendingSchedule = null;
    if (pending != null) await reschedule(pending);
  }

  /// Cihaz saat dilimini `tz.local` olarak ayarlar.
  ///
  /// Önceki davranış `catch (_)` ile yutuyordu: `timezone` paketinde local
  /// konum **UTC** olduğu için `FlutterTimezone` herhangi bir nedenle hata
  /// verdiğinde tüm hatırlatıcılar UTC'de planlanıyordu (TR için 3 saatlik
  /// sessiz kayma). Artık hata loglanır, sabit ofset biçimleri (`GMT+03:00`)
  /// çözülür ve başarısızlık sessizce yutulmaz.
  Future<void> applyLocalTimeZone() async {
    if (kIsWeb) return;
    if (!_tzReady) {
      tzdata.initializeTimeZones();
      _tzReady = true;
    }
    String platformZone;
    try {
      platformZone = await FlutterTimezone.getLocalTimezone();
    } catch (e, s) {
      AppLog.w('Cihaz saat dilimi okunamadı, UTC planlamaya düşülüyor', e, s);
      _tzName = null;
      return;
    }
    final resolved = resolveTimeZone(platformZone);
    if (resolved == null) {
      AppLog.w(
        'Bilinmeyen cihaz saat dilimi "$platformZone" — UTC planlamaya düşülüyor',
      );
      _tzName = null;
      return;
    }
    tz.setLocalLocation(resolved);
    _tzName = resolved.name;
  }

  /// Cihaz saat dilimi değiştiğinde `tz.local` tazelenir ve kayıtlı
  /// hatırlatıcılar yeni dilimde yeniden planlanır (DST kayması böyle
  /// giderilir). Uygulama arka plandayken dilim değişirse yeniden açılışta
  /// [init] üzerinden zaten uygulanır.
  Future<void> refreshTimeZone() async {
    final before = _tzName;
    await applyLocalTimeZone();
    if (_tzName == before) return;
    AppLog.i(
      'Saat dilimi değişti ($before → $_tzName); hatırlatıcılar yeniden planlanıyor',
    );
    for (final watcher in List.of(_timezoneWatchers)) {
      watcher();
    }
  }

  /// Saat dilimi değişiminde "hatırlatıcıları yeniden planla" geri çağrısı
  /// ekler. [ReminderSettingsNotifier] bunu `build()` sırasında bağlar.
  void addTimezoneWatcher(void Function() onChanged) {
    _timezoneWatchers.add(onChanged);
  }

  void removeTimezoneWatcher(void Function() onChanged) {
    _timezoneWatchers.remove(onChanged);
  }

  Future<void> _ensurePermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.requestNotificationsPermission();
    _exactAllowed =
        await android.requestExactAlarmsPermission() ?? true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    final meal = _mealForId(response.id);
    if (meal == null) return;
    if (response.actionId == actionSkip ||
        response.actionId == actionSnooze) {
      _actions.add('${response.actionId}:${meal.name}');
    } else {
      // Gövdeye tıklama — aksiyon yok, sadece akış.
      _actions.add(actionOpen);
    }
  }

  MealType? _mealForId(int? id) {
    if (id == null) return null;
    for (final meal in MealType.values) {
      if (id == mealReminderId(meal) || id == snoozeReminderId(meal)) {
        return meal;
      }
    }
    return null;
  }

  /// Öğün hatırlatıcılarını (yeniden) planlar; kapalı öğünler iptal edilir.
  ///
  /// Servis henüz `init()` edilmediyse istek biriktirilir; `init` bitince
  /// uygulanır. Böylece uygulama açılışındaki kalıcı ayarlar sessizce
  /// kaybolmaz.
  Future<void> reschedule(Map<MealType, MealReminder> meals) async {
    if (kIsWeb) return;
    if (!_initialized) {
      _pendingSchedule = Map.of(meals);
      return;
    }
    for (final meal in MealType.values) {
      await _plugin.cancel(mealReminderId(meal));
      await _plugin.cancel(snoozeReminderId(meal));
    }
    for (final meal in reminderMeals) {
      final reminder = meals[meal];
      if (reminder == null || !reminder.enabled) continue;
      await _scheduleDaily(
        mealReminderId(meal),
        meal,
        reminder.hour,
        reminder.minute,
        payload: 'daily_reminder:${meal.name}',
      );
    }
  }

  /// Bir sonraki `reschedule`'ın tetiklenip tetiklenmeyeceğini bilmeden
  /// "ön plan" alınmış mı diye bakmak için (test/teşhis amaçlı).
  @visibleForTesting
  bool get hasPendingSchedule => _pendingSchedule != null;

  Future<void> _scheduleDaily(
    int id,
    MealType meal,
    int hour,
    int minute, {
    required String payload,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = nextDailyOccurrence(
      now: now,
      hour: hour,
      minute: minute,
    );

    await _plugin.zonedSchedule(
      id,
      meal.notifTitleKey.tr(),
      meal.notifBodyKey.tr(),
      when,
      _details(meal),
      androidScheduleMode: _exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  /// "1 saat ertele" — günlük plan korunur, ek olarak 1 saat sonra tek seferlik
  /// hatırlatma gösterir.
  Future<void> snoozeOneHour(MealType meal) async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(snoozeReminderId(meal));
    await _plugin.zonedSchedule(
      snoozeReminderId(meal),
      meal.notifTitleKey.tr(),
      meal.notifBodyKey.tr(),
      tz.TZDateTime.now(tz.local).add(const Duration(hours: 1)),
      _details(meal, showActions: false),
      androidScheduleMode: _exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'snooze_reminder:${meal.name}',
    );
  }

  NotificationDetails _details(MealType meal, {bool showActions = true}) {
    final actions = showActions
        ? [
            AndroidNotificationAction(
              actionSnooze,
              'notifications.snoozeHour'.tr(),
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              actionSkip,
              meal.notifSkipKey.tr(),
              showsUserInterface: false,
            ),
          ]
        : null;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'Günlük hatırlatıcılar',
        channelDescription: 'Öğün hatırlatmaları',
        importance: Importance.high,
        priority: Priority.high,
        color: const Color(0xFF00C7B7),
        actions: actions,
      ),
    );
  }

  void dispose() {
    _timezoneWatchers.clear();
    unawaited(_actions.close());
  }
}
