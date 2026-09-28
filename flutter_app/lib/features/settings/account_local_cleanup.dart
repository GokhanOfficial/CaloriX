import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/reminder_settings.dart';
import '../../core/observability/app_logger.dart';
import '../../core/widgets/widget_bridge.dart';
import '../../core/widgets/widget_settings.dart';
import '../../core/widgets/widget_strings.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/diary_repository.dart';
import '../../data/repositories/food_repository.dart';
import '../../data/repositories/profile_repository.dart';

/// Hesap silme sonrası **cihazdaki** verileri temizler (KVKK).
///
/// ## Neden ayrı dosya?
///
/// `delete-account` sunucu tarafını (veritabanı + storage + auth kaydı)
/// temizler. Ama **cihazda** kalan veri de silinmezse KVKK ihlali olur:
/// aynı cihazda yeni bir hesapla girildiğinde eski hesabın öğünleri,
/// sohbeti ve hatırlatıcıları **görünür** kalır. `home_widget` veri kanalı
/// (`FlutterSharedPreferences`) cihazın ana ekranında **kalorileri** gösterir;
/// `_WidgetBridgeScope` bunu `currentUserProvider` dinleyerek temizliyor olsa
/// bile (bkz. `widget_bridge.dart:292`), bu yalnızca **state yayını**dır —
/// `reminder_*`, `widget_*`, `theme` gibi kalıcı anahtarlar kalır.
///
/// ## Tasarım kararı: `SharedPreferences.clear()` **kullanılmaz**
///
/// Ölçülen gerçek (2026-09-28): `supabase_flutter-2.17.2`
/// `src/supabase.dart:130-134` → oturumu `SharedPreferencesLocalStorage`
/// ile **aynı depoda** şu anahtarla saklar:
///
/// ```text
/// sb-<host>-auth-token          ← oturum (JWT + refresh token)
/// SharedPreferencesGotrueAsyncStorage → PKCE doğrulayıcı anahtarları
/// ```
///
/// Yani `prefs.clear()` çağırsak **oturum da silinirdi**. Bu, `signOut()`
/// yolunu görünmez biçimde devre dışı bırakır ve yarı uygulanmış bir
/// oturumun kalmasına yol açabilirdi. Bunun yerine **yalnızca uygulamaya ait
/// anahtarlar** tek tek silinir ([appOwnedPrefKeys]); oturum temizliği
/// `AuthRepository.signOut()`'un işidir ve bu yüzden **ayrı** adımdır.
///
/// ## Kaynak doğrulama tablosu (tahmin yok)
///
/// | Temizlenen şey | Gerçek çağrılan fonksiyon | Kaynak |
/// |---|---|---|
/// | Öğün hatırlatıcıları (SharedPreferences) | `prefs.remove('reminder_<meal>_enabled/_hour/_minute')` + legacy `reminder_enabled/_hour/_minute` | `reminder_settings.dart:32-38` |
/// | **Planlı** bildirimler (Android/iOS) | `NotificationService.instance.reschedule({})` — tüm öğünleri iptal eder | `notification_service.dart:274-290` |
/// | Widget ayarları | `WidgetSettingsKeys.*` (9 anahtar) | `widget_settings.dart:75-84` |
/// | Tema | `'theme'` | `app_theme.dart:235` |
/// | Kamera tercihi | `'camera_preference'` | `camera_preference.dart:28` |
/// | Güncelleme önbelleği / susturulan sürüm | `'update_manifest_cache'`, `'update_dismissed_code'` | `update_checker.dart:67,150` |
/// | Ana ekran widget'ı veri kanalı | `WidgetBridge.publishState(state: WidgetBridge.stateSignedOut, …)` | `widget_bridge.dart:119-132` |
/// | Riverpod state (profil, günlük veri, sohbet, yemekler) | `ref.invalidate(...)` | aşağıdaki [invalidatedProviders] |
class AccountLocalCleanup {
  const AccountLocalCleanup(this._ref);

  final Ref _ref;

  /// `shared_preferences`'ta uygulamaya ait silinecek anahtarlar.
  ///
  /// **Salt okunur** (test edilebilir): listede değişiklik yapılabilir.
  static List<String> get appOwnedPrefKeys => [
        // --- Tema (`app_theme.dart:235`) ---
        'theme',
        // --- Kamera tercihi (`camera_preference.dart:28`) ---
        'camera_preference',
        // --- Güncelleme denetleyicisi (`update_checker.dart:67,150`) ---
        'update_manifest_cache',
        'update_dismissed_code',
        // --- Widget ayarları (`widget_settings.dart:75-84`) ---
        for (final key in [
          WidgetSettingsKeys.showMacros,
          WidgetSettingsKeys.showWater,
          WidgetSettingsKeys.showWeight,
          WidgetSettingsKeys.weeklyAvg,
          WidgetSettingsKeys.weeklyDaysOnTarget,
          WidgetSettingsKeys.encouragement,
          WidgetSettingsKeys.nudgeEnabled,
          WidgetSettingsKeys.nudgeHour,
          WidgetSettingsKeys.nudgeMinute,
        ])
          key,
        // --- Öğün hatırlatıcıları (`reminder_settings.dart:32-38`) ---
        for (final meal in MealType.values) ...[
          'reminder_${meal.name}_enabled',
          'reminder_${meal.name}_hour',
          'reminder_${meal.name}_minute',
        ],
        // v1.2.0 tekil anahtarları — göç edilmemiş olabilir.
        'reminder_enabled',
        'reminder_hour',
        'reminder_minute',
      ];

  /// Silme sonrası **geçersiz kılınacak** (yeniden okunacak) provider'lar.
  ///
  /// `ref.invalidate` çağırmak, provider'ın bir sonraki okunduğunda yeniden
  /// hesaplanmasını sağlar. Bu **container'ı yok etmez** (uygulama çalışmaya
  /// devam eder) ama bellekteki öğün/sohbet/favori listelerini düşürür.
  ///
  /// Kapsam, [appOwnedPrefKeys] ile eşleşir:
  ///  - `profileProvider` — profil (sunucuda silindi)
  ///  - `dailyDataProvider` — günlük veri
  ///  - `activeChatThreadIdProvider` — sohbet thread'i
  ///  - `favoriteFoodsProvider` / `favoriteIdsProvider` — favoriler
  ///  - `frequentFoodsProvider` / `recentFoodsProvider` — son kullanılanlar
  ///  - `widgetSettingsProvider` — widget ayarları (kalıcı değer silindi)
  ///  - `reminderSettingsProvider` — hatırlatıcılar (kalıcı değer silindi)
  static void invalidateAccountState(Ref ref) {
    for (final provider in accountScopedProviders) {
      ref.invalidate(provider);
    }
  }

  /// `ref.invalidate` edilecek provider listesi (test edilebilir, sabit).
  static final List<ProviderOrFamily> accountScopedProviders = [
    profileProvider,
    dailyDataProvider,
    selectedDateProvider,
    activeChatThreadIdProvider,
    favoriteFoodsProvider,
    favoriteIdsProvider,
    frequentFoodsProvider,
    recentFoodsProvider,
    widgetSettingsProvider,
    reminderSettingsProvider,
  ];

  /// Silme sonrası cihaz temizliğini yapar.
  ///
  /// Sıra önemlidir:
  ///  1. **Planlı bildirimler** — hesabın hatırlatıcıları iptal edilir;
  ///     aksi hâlde silinmiş hesabın adına bildirim gelmeye devam eder.
  ///  2. **Ana ekran widget'ı** — `signedOut` durumuna alınır, böylece
  ///     şifreli ekranda eski kaloriler görünmez.
  ///  3. **Kalıcı anahtarlar** — `shared_preferences` temizlenir.
  ///  4. **Riverpod state** — bellekteki veri düşürülür.
  ///
  /// **Hiçbir adım istisna fırl atmaz.** Temizlik başarısız olsa bile
  /// kullanıcıya "hesabınız silindi" demek yanlış olurdu; o yüzden
  /// [AccountLocalCleanupResult] geri döner ve çağıran loglar. Sıfırlama
  /// tekrar denendiğinde aynı sonucu üretir (idempotent).
  Future<AccountLocalCleanupResult> run() async {
    final result = AccountLocalCleanupResult();

    // 1) Planlı yerel bildirimler (web'de no-op).
    result.notificationsCancelled = await _cancelScheduledNotifications();

    // 2) Ana ekran widget'ı → nötr durum.
    result.widgetSignedOut = await _publishSignedOutWidget();

    // 3) Kalıcı anahtarlar.
    result.prefsCleared = await _clearAppPrefs();

    // 4) Bellekteki veri.
    invalidateAccountState(_ref);
    result.stateInvalidated = true;

    return result;
  }

  /// `NotificationService.reschedule({})` — tüm öğün planlarını iptal eder.
  ///
  /// Neden `{}` ve neden `reschedule`: `notification_service.dart:287-290`
  /// `MealType.values` için `cancel(mealReminderId)` + `cancel(snoozeReminderId)`
  /// çağırır, ardından **yalnızca `enabled` olan** hatırlatıcıları yeniden
  /// planlar. Boş harita ⇒ hiçbir şey planlanmaz, hepsi iptal edilir.
  /// `_plugin.cancel` yerine doğrudan çağrılabilecek genel bir "iptal et"
  /// API'si serviste **yok**; `reschedule({})` tek doğru giriş noktası.
  Future<bool> _cancelScheduledNotifications() async {
    try {
      await NotificationService.instance.reschedule(const {});
      return true;
    } catch (e, s) {
      AppLog.w('Hesap sonrası hatırlatıcılar iptal edilemedi', e, s);
      return false;
    }
  }

  /// Widget'ı `signedOut` durumuna alır.
  ///
  /// Web'de `home_widget` yok → atlanır (kayıt zaten orada olmaz).
  Future<bool> _publishSignedOutWidget() async {
    if (kIsWeb) return true;
    try {
      await WidgetBridge.publishState(
        state: WidgetBridge.stateSignedOut,
        strings: WidgetStrings.current(),
        localeCode: 'en',
      );
      return true;
    } catch (e, s) {
      AppLog.w('Hesap sonrası widget durumu sıfırlanamadı', e, s);
      return false;
    }
  }

  /// Uygulamaya ait `shared_preferences` anahtarlarını siler.
  ///
  /// Oturum anahtarı (`sb-<host>-auth-token`) **bilinçli olarak korunur** —
  /// bkz. sınıf dokümanı, "Tasarım kararı".
  Future<bool> _clearAppPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in appOwnedPrefKeys) {
        await prefs.remove(key);
      }
      return true;
    } catch (e, s) {
      AppLog.w('Hesap sonrası yerel tercihler temizlenemedi', e, s);
      return false;
    }
  }
}

/// Temizliğin hangi adımlarının başarılı olduğu (tanılamaya ve teste açık).
///
/// `signOut()` bu sonuca bakmaz: oturum düşürmek **her zaman** yapılır
/// (kullanıcı kendi hesabını silmiş, oturum kalmamalıdır), ama temizlik
/// başarısız olursa **loglanır** ve kullanıcıya "cihazınızı temizleyin"
/// hatırlatması gösterebilir.
class AccountLocalCleanupResult {
  AccountLocalCleanupResult({
    this.notificationsCancelled = false,
    this.widgetSignedOut = false,
    this.prefsCleared = false,
    this.stateInvalidated = false,
  });

  // `run()` adım adım doldurduğu için `final` **değil** — bu sınıf
  // yalnızca [AccountLocalCleanup.run] içinde mutasyona uğrar.
  bool notificationsCancelled;
  bool widgetSignedOut;
  bool prefsCleared;
  bool stateInvalidated;

  /// Her adım başarılı mı?
  bool get complete =>
      notificationsCancelled && widgetSignedOut && prefsCleared && stateInvalidated;
}

final accountLocalCleanupProvider = Provider<AccountLocalCleanup>((ref) {
  return AccountLocalCleanup(ref);
});
