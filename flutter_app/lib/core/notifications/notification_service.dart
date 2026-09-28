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

  /// Saat dilimi çözülemedi mi? (sessiz UTC düşüşü)
  ///
  /// `true` ise hatırlatıcılar **UTC'de** planlanıyor — TR için 3 saat,
  /// ABD için 5-8 saatlik sessiz kayma. `AppLog` bunu kaydeder ama release'de
  /// Sentry DSN boşsa log tamamen kaybolur (bkz. `app_logger.dart:36`), yani
  /// kullanıcı hatırlatıcının yanlış saatte geldiğini "sihirbazlık" olarak
  /// yaşıyor. Bu bayrak ayar ekranının uyarı göstermesini mümkün kılar.
  bool get timeZoneUnresolved => _tzResolvedOnce && _tzName == null;

  /// `applyLocalTimeZone` en az bir kez çalıştı mı? (`timeZoneUnresolved`
  /// ancak bu anlamlı — aksi halde her yeni servis "çözülmemiş" görünür.)
  bool _tzResolvedOnce = false;

  /// Saat dilimi değiştiğinde çağrılacak geri çağrılar. Uygulama ön planı
  /// (arkada reschedule) tarafından doldurulur.
  final List<void Function()> _timezoneWatchers = [];

  /// `tz` veritabanı başlatıldı mı — `reschedule` erken çağrıldığında
  /// `tz.local`'in UTC olmasını önler.
  bool _tzReady = false;

  /// Android 12+ exact alarm izni yoksa inexact planlamaya düşer.
  bool _exactAllowed = true;

  /// Kullanıcı Android 13+ bildirim iznini vermemiş mi? (`null` = bilinmiyor)
  ///
  /// `areNotificationsEnabled()` **her planlamada** sorulur
  /// ([_refreshPermissions]): kullanıcı ayarlardan geri dönerken izni açmış
  /// olabilir. Reddedildiyse planlama yine de yapılır — kullanıcı ayarı
  /// silmeden önce izni geri açarsa bildirim doğru saatte gelmeye başlar.
  bool? _notificationsAllowed;

  /// Son uygulanan planlama sonucu — çağıran (ayarlar ekranı) bunu okuyup
  /// kullanıcıya "izin yok / planlama başarısız" uyarısı gösterebilir.
  NotificationScheduleOutcome _lastOutcome =
      const NotificationScheduleOutcome();

  /// `reschedule`/`snoozeOneHour` sonrası planlama durumu.
  NotificationScheduleOutcome get lastScheduleOutcome => _lastOutcome;

  /// Kullanıcı Android 13+ bildirim iznini vermemiş mi? (`null` = bilinmiyor)
  ///
  /// `areNotificationsEnabled()` **her planlamada** sorulur
  /// ([_refreshPermissions]): kullanıcı ayarlardan geri dönerken izni açmış
  /// olabilir. Reddedildiyse planlama yine de yapılır — kullanıcı ayarı
  /// silmeden önce izni geri açarsa bildirim doğru saatte gelmeye başlar.
  bool? get notificationsAllowed => _notificationsAllowed;

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
    _tzResolvedOnce = true;
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

  /// Bildirim + tam alarm izinlerini ister ve sonucu kaydeder.
  ///
  /// `requestExactAlarmsPermission()` **yalnızca init'te bir kez** sorulur:
  /// Android 12+ bu çağrı bir sistem ayarları ekranı açır ve her yeniden
  /// planlamada sorulursa kullanıcı ayar kaydettikçe ayarlar ekranına
  /// ışınlanır. Bunun yerine her `reschedule`'te **okuma** yapılır
  /// ([_refreshPermissions]).
  Future<void> _ensurePermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    // Asıl doğrulama `areNotificationsEnabled()` ile yapılır
    // (bkz. [_refreshPermissions] — aynı turda tazelenir).
    await android.requestNotificationsPermission();
    _exactAllowed = await android.requestExactAlarmsPermission() ?? true;
    await _refreshPermissions();
  }

  /// İzin durumunu **yeniden okur** (kullanıcı ayarlardan dönerken çağrılır).
  ///
  /// Önceki davranış iki sorunu birden taşıyordu:
  ///  * `_exactAllowed` yalnızca `init`'te bir kez belirlendiği için
  ///    kullanıcı tam alarm iznini sonradan kapatırsa uygulama hâlâ
  ///    `exactAllowWhileIdle` gönderiyor, `zonedSchedule` başarısız oluyor
  ///    ve hatırlatıcılar **sessizce hiç gelmiyordu**.
  ///  * `POST_NOTIFICATIONS` reddi hiçbir yerde görünmüyordu.
  ///
  /// İki okuma da platform kanalına gittiği için her ayar değişiminde
  /// (nadir, kullanıcı eylemi) çağırmak kabul edilebilir; her `build`'de
  /// çağırmak değil.
  Future<void> _refreshPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      _notificationsAllowed = await android.areNotificationsEnabled();
      _exactAllowed = await android.canScheduleExactNotifications() ??
          _exactAllowed;
    } catch (e, s) {
      // Platform kanalı yok (test/iOS): mevcut değerleri koru.
      AppLog.w('Bildirim izinleri okunamadı', e, s);
    }
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

    // İzin durumu her planlamada yeniden okunur: kullanıcı ayarlardan
    // dönerken tam alarm iznini vermiş/verilmemiş olabilir. Önceki kod
    // bunu yalnızca init'te yapıyordu, `exactAllowWhileIdle` gönderimi
    // başarısız olup hatırlatıcılar **sessizce hiç gelmiyordu**.
    await _refreshPermissions();

    for (final meal in MealType.values) {
      await _plugin.cancel(mealReminderId(meal));
      await _plugin.cancel(snoozeReminderId(meal));
    }

    var failed = 0;
    for (final meal in reminderMeals) {
      final reminder = meals[meal];
      if (reminder == null || !reminder.enabled) continue;
      final ok = await _scheduleDaily(
        mealReminderId(meal),
        meal,
        reminder.hour,
        reminder.minute,
        payload: 'daily_reminder:${meal.name}',
      );
      if (!ok) failed++;
    }
    _lastOutcome = NotificationScheduleOutcome(
      scheduledCount: reminderMeals.where((m) {
        final r = meals[m];
        return r != null && r.enabled;
      }).length,
      failedCount: failed,
      notificationsAllowed: _notificationsAllowed,
      exactAllowed: _exactAllowed,
    );
  }

  /// Bir sonraki `reschedule`'ın tetiklenip tetiklenmeyeceğini bilmeden
  /// "ön plan" alınmış mı diye bakmak için (test/teşhis amaçlı).
  @visibleForTesting
  bool get hasPendingSchedule => _pendingSchedule != null;

  /// Günlük hatırlatıcıyı planlar. Başarı durumunu döner.
  ///
  /// Neden `try/catch`: `zonedSchedule` tam alarm izni olmadığında
  /// `ExactAlarmPermissionException` fırlatıyor ve **istisna, planlanan
  /// diğer öğünlerin de planlanmasını engelliyordu** — bir öğünün planlama
  /// hatası diğer ikisini de sessizce bırakıyordu. Şimdi hata yakalanır,
  /// loglanır ve [reschedule] devam eder.
  Future<bool> _scheduleDaily(
    int id,
    MealType meal,
    int hour,
    int minute, {
    required String payload,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    final when = nextDailyOccurrence(
      now: now,
      hour: hour,
      minute: minute,
    );

    try {
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
      return true;
    } catch (e, s) {
      AppLog.w('Hatırlatıcı planlanamadı (${meal.name})', e, s);
      return false;
    }
  }

  /// "1 saat ertele" — günlük plan korunur, ek olarak 1 saat sonra tek seferlik
  /// hatırlatma gösterir.
  ///
  /// [reschedule] ile aynı gerekçeyle hata yutulur: erteleme planlanamazsa
  /// istisna `app.dart`'deki aksiyon işleyicisine kaçıyordu.
  Future<void> snoozeOneHour(MealType meal) async {
    if (kIsWeb || !_initialized) return;
    await _plugin.cancel(snoozeReminderId(meal));
    try {
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
    } catch (e, s) {
      AppLog.w('Erteleme planlanamadı (${meal.name})', e, s);
    }
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

/// Bir [NotificationService.reschedule] çağrısının sonucu.
///
/// Amaç: "hatırlatıcılar çalışmıyor" şikâyetini teşhis edilebilir kılmak.
/// Önceki kodda planlama hataları ya istisna fırlatıp diğer öğünlerin
/// planlanmasını engelliyordu ya da tamamen sessizce yutuluyordu; kullanıcı
/// tek gözlemiyle "bildirim gelmiyor" diyebiliyordu.
@immutable
class NotificationScheduleOutcome {
  const NotificationScheduleOutcome({
    this.scheduledCount = 0,
    this.failedCount = 0,
    this.notificationsAllowed,
    this.exactAllowed = true,
  });

  /// Planlanmayı denenen öğün sayısı.
  final int scheduledCount;

  /// `zonedSchedule` istisna fırlattığı öğün sayısı.
  final int failedCount;

  /// `areNotificationsEnabled()` sonucu (`null` = bilinmiyor/okunamadı).
  final bool? notificationsAllowed;

  /// `canScheduleExactNotifications()` sonucu — `false` ise planlama inexact
  /// moda düşmüş demektir (birkaç dakikalık kayma olabilir).
  final bool exactAllowed;

  /// En az bir planlama başarısız oldu mu?
  bool get hasFailure => failedCount > 0;

  /// Bildirim izni kapalı mı? (Android 13+; `null` ise bilinmiyor.)
  bool get notificationsDisabled => notificationsAllowed == false;

  /// Kullanıcıya gösterilecek bir uyarı gerekiyor mu?
  ///
  /// `notificationsDisabled` **en kritik** durum: plan doğru kurulmuştur ama
  /// Android hiç göstermeyecek. `failedCount > 0` ikinci sırada, tam alarm
  /// eksikliği üçüncüde (kullanıcı hatırlatıcıyı biraz geç alabilir).
  bool get needsUserAttention =>
      notificationsDisabled || hasFailure || !exactAllowed;

  @override
  String toString() => 'NotificationScheduleOutcome('
      'scheduled=$scheduledCount, failed=$failedCount, '
      'allowed=$notificationsAllowed, exact=$exactAllowed)';
}
