/// Hesap silme sonrası **cihaz** temizliği (A4r4b, Tur 10 — KVKK).
///
/// ## Bu test neden var?
///
/// `delete-account` sunucuyu temizler; cihazdaki veri kalırsa aynı cihazda
/// bir sonraki girişte **silinmiş hesabın** verileri görünür (KVKK ihlali) ve
/// ana ekran widget'ı eski kalorileri göstermeye devam eder. Bu test,
/// `AccountLocalCleanup`'in **gerçek anahtarları** gerçekten sildiğini ölçer —
/// fonksiyon adları uydurulmamış, kaynaktan okunmuştur (bkz. sınıf dokümanı).
///
/// ## Ölçülen gerçek: `clear()` **kullanılmaz**
///
/// `supabase_flutter-2.17.2` (`src/supabase.dart:130-134`) oturumu
/// `shared_preferences`'ın **aynı deposunda** `sb-<host>-auth-token`
/// anahtarında tutar. `prefs.clear()` çağırsak oturum da silinirdi. Bu
/// test, temizlikten sonra oturum anahtarının **durduğunu** ayrıca doğrular.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calorix/core/config/camera_preference.dart';
import 'package:calorix/features/settings/account_local_cleanup.dart';
import 'package:calorix/core/widgets/widget_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `AccountLocalCleanup.run()` iki platform kanalına gider:
  //  - `home_widget` (`WidgetBridge.publishState` → `HomeWidgetSave.saveWidgetData`)
  //  - `flutter_local_notifications` (`reschedule` → `cancel`/`zonedSchedule`)
  // Test ortamında bu kanalların **mock** olmaması `MissingPluginException`
  // verir; `publish` bunu içeride yakalar ama `NotificationsService`
  // tarafındaki çağrılar **asılı** kalabilir. Kanal adları paket
  // kaynaklarından okundu (`home_widget-0.10.0/lib/src/home_widget.dart:15`).
  const homeWidgetChannel = MethodChannel('home_widget');
  const notificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');

  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    // Önceki testlerin kalıntısı olmasın diye **her seferinde** sıfırdan
    // başlanır; yalnızca temizlikten sonra "yok edildi" denetlenen
    // anahtarlar doldurulur.
    //
    // ⚠️ Sıra önemli: `setMockInitialValues` **kanal mock'larından önce**
    // gelmeli, çünkü `SharedPreferences.getInstance()` bunu okur.
    SharedPreferences.setMockInitialValues({
      'theme': 'light',
      'camera_preference': 'native',
      'update_manifest_cache': '{"versionCode":99}',
      'update_dismissed_code': 99,
      'widget_show_macros': false,
      'widget_show_water': false,
      'widget_show_weight': true,
      'widget_weekly_avg': false,
      'widget_weekly_target_days': false,
      'widget_encouragement': false,
      'widget_nudge_enabled': true,
      'widget_nudge_hour': 21,
      'widget_nudge_minute': 30,
      'reminder_breakfast_enabled': true,
      'reminder_breakfast_hour': 8,
      'reminder_breakfast_minute': 0,
      'reminder_lunch_enabled': true,
      'reminder_lunch_hour': 13,
      'reminder_lunch_minute': 0,
      'reminder_dinner_enabled': true,
      'reminder_dinner_hour': 20,
      'reminder_dinner_minute': 0,
      'reminder_snack_enabled': true,
      'reminder_snack_hour': 16,
      'reminder_snack_minute': 0,
      // Göç edilmemiş v1.2.0 tekil anahtarları.
      'reminder_enabled': true,
      'reminder_hour': 7,
      'reminder_minute': 30,
      // Oturum — **korunmalı**.
      'sb-test-auth-token': 'jwt-deger',
    });

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [homeWidgetChannel, notificationsChannel]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        // `initialize` / `cancel` / `zonedSchedule` / izin sorguları.
        // Hepsini "başarılı ve bildirim yok" diye yanıtla; testin amacı
        // platform davranışını değil **hangi fonksiyonun çağrıldığını**
        // ölçmek.
        return null;
      });
    }
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [homeWidgetChannel, notificationsChannel]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('appOwnedPrefKeys: tema, kamera, güncelleme, widget, hatırlatıcı',
      () async {
    prefs = await SharedPreferences.getInstance();
    final keys = AccountLocalCleanup.appOwnedPrefKeys.toSet();

    // Her kategoriden en az bir anahtar listelenmiş olmalı.
    expect(keys, contains('theme'));
    expect(keys, contains(CameraPreferenceNotifier.prefsKey));
    expect(keys, contains(WidgetSettingsKeys.showMacros));
    expect(keys, contains(WidgetSettingsKeys.nudgeMinute));
    expect(keys, contains('reminder_breakfast_enabled'));
    // 4 öğün × 3 anahtar = 12 hatırlatıcı anahtarı (+ 3 legacy).
    expect(keys.where((k) => k.startsWith('reminder_')).length, 12 + 3);
  });

  test('appOwnedPrefKeys: oturum anahtarı LİSTEDE DEĞİL', () {
    // `clear()` yerine tek tek silme kararının **gerekçesi** budur.
    expect(AccountLocalCleanup.appOwnedPrefKeys,
        isNot(contains('sb-test-auth-token')));
  });

  test('run(): uygulama anahtarları silinir', () async {
    prefs = await SharedPreferences.getInstance();

    final result = await _runCleanup();

    expect(result.prefsCleared, isTrue);
    for (final key in AccountLocalCleanup.appOwnedPrefKeys) {
      expect(prefs.get(key), isNull, reason: '"$key" silinmeliydi');
    }
  });

  test('run(): oturum anahtarı KALIR (clear() kullanılmaz)', () async {
    prefs = await SharedPreferences.getInstance();

    await _runCleanup();

    // Silme sonrası `signOut()` zaten çağrılıyor; ama temizliğin kendisi
    // oturumu **sessizce** düşürmemeli — iki sorumluluk karışmamalı.
    expect(prefs.getString('sb-test-auth-token'), 'jwt-deger');
  });

  test('run(): dört adımın tamamı başarılı', () async {
    final result = await _runCleanup();
    expect(result.notificationsCancelled, isTrue,
        reason: 'hatırlatıcılar planlanmış durumda kalmamalı');
    expect(result.widgetSignedOut, isTrue,
        reason: 'ana ekran widget\'ı nötr duruma geçmeli');
    expect(result.prefsCleared, isTrue);
    expect(result.stateInvalidated, isTrue);
    expect(result.complete, isTrue);
  });

  test('run(): idempotent — ikinci çalıştırma da patlamaz', () async {
    // Aynı temizlik iki kez yapılabilir (kullanıcı çift tıklar / retry).
    await _runCleanup();
    final second = await _runCleanup();
    expect(second.complete, isTrue);
  });

  test('accountScopedProviders: profil, günlük veri, sohbet, favoriler kapsamda',
      () {
    // Sunucuda silinen her veri türü için bellek karşılığı düşürülmeli.
    expect(AccountLocalCleanup.accountScopedProviders.length,
        greaterThanOrEqualTo(8));
  });
}

/// Temizliği bir `ProviderContainer` üzerinden çalıştırır.
///
/// `ProviderScope` yerine doğrudan container: temizlik bir **veri katmanı**
/// işidir, widget ağacına ihtiyacı yoktur.
Future<AccountLocalCleanupResult> _runCleanup() async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container.read(accountLocalCleanupProvider).run();
}
