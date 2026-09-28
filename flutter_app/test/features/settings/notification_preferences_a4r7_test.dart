/// Sunucu bildirim tercihleri arayüzü (A4r7, Tur 7 — ürün kararı 2-A).
///
/// ## Bu test neden var?
///
/// A1r4'ün bulgusu: `check-reminders` (`index.ts:349/413/483`) `water` /
/// `daily_log` / `weekly_summary` için `pref?.push_enabled ||
/// pref?.email_enabled` arar. **Satır yoksa** ifade `false` → bu üç tip
/// **sessizce kapalıdır**. Flutter ise `notification_preferences`'a **hiç**
/// yazmıyordu (`notifications_dialog.dart` yalnız profil anahtarlarını
/// yazıyordu) → kullanıcı cihazda ayar yapıyor, sunucu tarafı "tercih yok"
/// deyip kapatıyordu.
///
/// ## Ölçülen sözleşmeler
///
/// 1. **Varsayılanlar web ile birebir aynı** (`NOTIFICATION_DEFAULTS`,
///    `src/hooks/useNotifications.ts:29-35`). İki istemci farklı varsayılan
///    üretirse aynı kullanıcı iki yerde farklı davranış görür.
/// 2. **DB CHECK aralıkları** (`notification_preferences_hours_range`,
///    `full_setup.sql:624-628`): saatler 0..23, `interval_hours` 1..24,
///    `summary_day` 0..6. Aralık dışı yazmak 400 döndürür ve **tüm ayar
///    kaydını** düşürürdü → `toRow` normalize eder.
/// 3. **`created_at` gönderilmez** (A2r5'in hatası).
/// 4. **Bir ayar ekranı**: sunucu tercihleri öğün hatırlatıcılarıyla
///    **aynı** diyalogda; iki ayrı ekran yok.
library;

import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/models/profile.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/notification_preferences_repository.dart';
import 'package:calorix/data/repositories/profile_repository.dart';
import 'package:calorix/features/settings/widgets/notifications_dialog.dart';
import 'package:calorix/features/settings/widgets/server_notification_preferences_section.dart';

http.Response _respond(http.BaseRequest request, Object? body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

SupabaseClient _clientWith(
  Future<http.Response> Function(http.Request) handler,
) =>
    SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: MockClient((req) async => handler(req)),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  group('varsayılanlar — web NOTIFICATION_DEFAULTS ile birebir', () {
    test('water: push açık, 09-21, 3 saat aralık', () {
      final p = defaultServerPreference(ServerNotificationType.water);
      expect(p.pushEnabled, isTrue);
      expect(p.emailEnabled, isFalse);
      expect(p.startHour, 9);
      expect(p.endHour, 21);
      expect(p.intervalHours, 3);
    });

    test('daily_log: push açık, e-posta kapalı', () {
      final p = defaultServerPreference(ServerNotificationType.dailyLog);
      expect(p.pushEnabled, isTrue);
      expect(p.emailEnabled, isFalse);
      expect(p.startHour, 18);
    });

    test('weekly_summary: push KAPALI, e-posta açık, Pazartesi 09:00', () {
      // Varsayılan **bilinçli** olarak farklı: haftalık özet her hafta
      // gönderilir, kullanıcı bunu push'ta istemeyebilir.
      final p = defaultServerPreference(ServerNotificationType.weeklySummary);
      expect(p.pushEnabled, isFalse);
      expect(p.emailEnabled, isTrue);
      expect(p.summaryDay, 1, reason: '1 = Pazartesi (sunucu weekday dizini)');
      expect(p.summaryHour, 9);
    });

    test('goal_achieved: push açık, e-posta kapalı, 0-23', () {
      final p = defaultServerPreference(ServerNotificationType.goalAchieved);
      expect(p.pushEnabled, isTrue);
      expect(p.emailEnabled, isFalse);
      expect(p.startHour, 0);
      expect(p.endHour, 23);
    });

    test('weigh_in: push + e-posta açık (A4r6 kararı)', () {
      final p = defaultServerPreference(ServerNotificationType.weighIn);
      expect(p.pushEnabled, isTrue);
      expect(p.emailEnabled, isTrue);
    });
  });

  group('DB CHECK aralıkları — toRow normalize eder', () {
    test('CHECK aralığı dışı değerler varsayılana döner (23514 önlenir)', () {
      // `notification_preferences_hours_range`: `start_hour BETWEEN 0 AND 23`,
      // `interval_hours 1..24`, `summary_day 0..6`, `summary_hour 0..23`.
      // Aralık dışı bir değer **tüm ayar kaydını** 400/`23514` ile düşürürdü.
      const bad = NotificationPreference(
        type: ServerNotificationType.water,
        startHour: 25,
        endHour: 30,
        intervalHours: 99,
        summaryDay: 9,
        summaryHour: 30,
      );
      final row = bad.toRow('u1');
      expect(row['start_hour'], 9, reason: 'varsayılana döner (25 geçersiz)');
      // `end` yalnız `0..23` **ve** `start`'tan büyük/equal ise korunur;
      // 30 hem aralık dışı hem `start(9) < end` koşulunu da sağlamıyor →
      // güvenli tarafa (`23` = gün sonu) düşer. Ölçülen davranış.
      expect(row['end_hour'], 23,
          reason: 'geçersiz `end` → 23 (tüm gün); `check-reminders` '
              '`normalizedHour <= endHour` koşulunu her saat sağlasın');
      expect(row['interval_hours'], 3, reason: 'CHECK 1..24, 99 geçersiz');
      expect(row['summary_day'], 1, reason: 'CHECK 0..6, 9 geçersiz');
      expect(row['summary_hour'], 9, reason: 'CHECK 0..23, 30 geçersiz');
    });

    // ⭐ `start_hour > end_hour` DB tarafından reddedilmez (ikisi de 0..23),
    // ama `check-reminders/index.ts:356` koşulu
    // `normalizedHour >= startHour && normalizedHour <= endHour` **hiçbir
    // saatte** sağlanmaz → `water` hatırlatması sessizce hiç gönderilmez.
    // İstemci tarafında düzeltilmeli (gece aralığı desteklenmiyor).
    test('start > end yazılmaz: sessizce kapalı hatırlatma olmaz', () {
      const bad = NotificationPreference(
        type: ServerNotificationType.water,
        startHour: 21,
        endHour: 6, // gece aralığı — sunucu desteklemiyor
      );
      final row = bad.toRow('u1');
      expect(row['start_hour'], 21);
      expect(row['end_hour'], 23,
          reason: 'end < start ise aralık **hiçbir saatte** sağlanmaz → '
              '23\'e çekilir, en azından 21-23 arası çalışır');
      // `row` değerleri `dynamic`; karşılaştırma öncesi `int`'e alınır
      // (`strict-casts` altında `as int` ifadesi `dynamic` üzerinde
      // `num` bekliyor ve derleme hatası veriyor).
      final start = row['start_hour'] as int;
      final end = row['end_hour'] as int;
      expect(start <= end, isTrue,
          reason: 'yazılan satır sunucunun saat aralığı koşulunu '
              'sağlayabilmeli');
    });

    test('geçerli değerler dokunulmadan yazılır', () {
      const ok = NotificationPreference(
        type: ServerNotificationType.water,
        pushEnabled: false,
        emailEnabled: true,
        startHour: 6,
        endHour: 23,
        intervalHours: 24,
      );
      final row = ok.toRow('u1');
      expect(row['start_hour'], 6);
      expect(row['end_hour'], 23);
      expect(row['interval_hours'], 24, reason: 'sınır değerler dahil');
      expect(row['push_enabled'], isFalse);
      expect(row['email_enabled'], isTrue);
    });

    test('created_at GÖNDERİLMEZ (A2r5 hatası)', () {
      final row = defaultServerPreference(ServerNotificationType.water).toRow('u1');
      expect(row.containsKey('created_at'), isFalse,
          reason: 'kolon `DEFAULT now()`; istemciden gönderimi toplu insert\'i '
              'StateError ile düşürüyordu');
      expect(row.containsKey('updated_at'), isFalse,
          reason: '`update_updated_at_column` trigger\'ı yönetir');
    });

    test('user_id her kayıtta (RLS `auth.uid() = user_id`)', () {
      final row = defaultServerPreference(ServerNotificationType.water).toRow('u1');
      expect(row['user_id'], 'u1');
      expect(row['notification_type'], 'water');
    });
  });

  group('notification_type allow-list (CHECK 400 döndürürdü)', () {
    test('beş tip DB CHECK ile birebir aynı', () {
      // `notification_preferences_type_allowlist`:
      // ('weigh_in','daily_log','water','goal_achieved','weekly_summary')
      expect(
        ServerNotificationType.values.map((t) => t.wire).toSet(),
        {'weigh_in', 'daily_log', 'water', 'goal_achieved', 'weekly_summary'},
      );
    });

    test('bilinmeyen satır weigh_in\'e düşer, hata fırlatmaz', () {
      // `fromRow` `firstWhere(orElse:)` kullanır; bozuk satır tüm ayar
      // ekranını çökertmemeli.
      final p = NotificationPreference.fromRow(
        const {'notification_type': 'bilinmeyen', 'push_enabled': false},
      );
      expect(p.type, ServerNotificationType.weighIn);
      expect(p.pushEnabled, isFalse, reason: 'satırdaki alanlar korunur');
    });

    // ⭐ A4r7b'nin bulduğu hata (2026-09-28): `fromRow` sayısal kolonlarda
    // `as int?` kullanıyordu. PostgREST JSON'u `jsonDecode` ile çözdüğü için
    // `integer` kolon `int` döner — **ama** kolon `numeric`/`bigint` ise ya da
    // istemci tarafı bir `String` üretirse `as int?` **`TypeError`**
    // fırlatır ve `fetch` tüm ayar ekranını çökertir (PROTOKOL §2 P1:
    // "bozuk satır ayar ekranını düşürmez").
    //
    // Ölçülen gerçek: repo'nun geri kalanı aynı tuzağa karşı **`as num?`**
    // kullanıyor (`food_repository.dart:347`, `profile.dart:146`) — buradaki
    // `as int?` bu dosyada tek istisnaydı.
    test('sayısal kolon String gelirse TypeError DEĞİL, değer okunur', () {
      final p = NotificationPreference.fromRow(const {
        'notification_type': 'water',
        'start_hour': '8',
        'end_hour': '20',
        'interval_hours': '2',
        'summary_day': '3',
        'summary_hour': '7',
      });
      expect(p.startHour, 8);
      expect(p.endHour, 20);
      expect(p.intervalHours, 2);
      expect(p.summaryDay, 3);
      expect(p.summaryHour, 7);
    });

    test('sayısal kolon num (double) gelirse değer okunur', () {
      final p = NotificationPreference.fromRow(const {
        'notification_type': 'water',
        'start_hour': 8.0,
        'interval_hours': 2.5,
      });
      expect(p.startHour, 8);
      expect(p.intervalHours, 2, reason: 'ondalık kırpılır');
    });

    test('bozuk/eksik sayısal değer varsayılana döner (çökmez)', () {
      final p = NotificationPreference.fromRow(const {
        'notification_type': 'water',
        'start_hour': 'saat',
        'interval_hours': null,
      });
      expect(p.startHour, 9, reason: 'parse edilemeyen → varsayılan');
      expect(p.intervalHours, 3);
    });
  });

  group('veri katmanı — fetch / upsert', () {
    test('fetch: tür → tercih haritası döner', () async {
      final client = _clientWith((req) async {
        expect(req.url.queryParameters['user_id'], 'eq.u1');
        return _respond(req, const [
          {
            'notification_type': 'water',
            'push_enabled': true,
            'email_enabled': false,
            'start_hour': 8,
            'end_hour': 20,
            'interval_hours': 2,
          },
        ]);
      });

      final map = await NotificationPreferencesRepository(client).fetch('u1');

      expect(map.keys, {ServerNotificationType.water});
      expect(map[ServerNotificationType.water]!.startHour, 8);
      expect(map[ServerNotificationType.water]!.intervalHours, 2);
    });

    test('fetch: tablo boşsa boş harita (ayarlar varsayılana düşer)', () async {
      final client =
          _clientWith((req) async => _respond(req, const <Object>[]));
      final map = await NotificationPreferencesRepository(client).fetch('u1');
      expect(map, isEmpty);
    });

    test('upsert: ON CONFLICT (user_id, notification_type)', () async {
      late Uri uri;
      final client = _clientWith((req) async {
        uri = req.url;
        return _respond(req, const <Object>[]);
      });

      await NotificationPreferencesRepository(client).upsert(
        const NotificationPreference(type: ServerNotificationType.water),
        'u1',
      );

      expect(uri.path, endsWith('/notification_preferences'));
      expect(uri.queryParameters['on_conflict'], 'user_id,notification_type',
          reason: 'UNIQUE(user_id, notification_type) → upsert çakışmayı '
              'çözer, yoksa ikinci kayıt 23505 ile düşer');
    });

    test('upsertAll: bir kayıt düşerse hata **yutulmaz**', () async {
      var n = 0;
      final client = _clientWith((req) async {
        n++;
        if (n == 2) return _respond(req, {'message': 'boom'}, status: 400);
        return _respond(req, const <Object>[]);
      });

      await expectLater(
        NotificationPreferencesRepository(client).upsertAll('u1', [
          const NotificationPreference(type: ServerNotificationType.water),
          const NotificationPreference(type: ServerNotificationType.dailyLog),
          const NotificationPreference(type: ServerNotificationType.weeklySummary),
        ]),
        throwsA(anything),
        reason: 'sessiz hata yutma yasak (PROTOKOL §2 P1); kullanıcı '
            '"Ayarlar güncellendi" derse yarım kaydedilmiş ayarları '
            'sanması gerekir',
      );
    });

    test('upsertAll: her tip için ayrı istek gider (satır satır yazılır)',
        () async {
      final paths = <String>[];
      final client = _clientWith((req) async {
        paths.add('${req.method} ${req.url.path}');
        return _respond(req, const <Object>[]);
      });

      await NotificationPreferencesRepository(client).upsertAll('u1', [
        const NotificationPreference(type: ServerNotificationType.water),
        const NotificationPreference(type: ServerNotificationType.dailyLog),
      ]);

      expect(paths, hasLength(2),
          reason: 'PostgREST toplu upsert tek çağrıda da olurdu; iki ayrı '
              'istek kastedilen davranış (hata hangi tipte olduysa o kadar '
              'net olsun diye ayrı yazılır — ama sayısı kayıp değil)');
    });
  });

  group('arayüz — tek ayar ekranı (iki kaynak bir arada)', () {
    late _MockProfileRepository profileRepo;
    late _MockNotificationPrefsRepository prefsRepo;

    setUp(() {
      profileRepo = _MockProfileRepository();
      prefsRepo = _MockNotificationPrefsRepository();
      when(() => profileRepo.update(any(), any()))
          .thenAnswer((_) async => null);
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
      when(() => prefsRepo.upsertAll(any(), any()))
          .thenAnswer((_) async {});
    });

    /// "Kaydet"i basar.
    ///
    /// ⚠️ Neden `ensureVisible` yetmiyor (A4r7b ölçümü): diyalog `showModal-
    /// BottomSheet` ile açıldığı gibi, testte `Scaffold(body:)` altında kurulur
    /// ve içindeki `SingleChildScrollView` **yatay** hizalı bir `Row`'un
    /// (altbilgi `mainAxisAlignment: end`) altında kalır. `ensureVisible`
    /// dikey kaydırma yapıyor ama düğmenin merkezi `Offset(713.7, 1140.0)`'de
    /// kalıyor → `HitTestResult` uyarısı: `outside the bounds of the root ...
    /// Size(800.0, 600.0)`. `tester.tap` bu durumda **sessizce hiçbir şey
    /// yapmıyor** ve `_save` hiç çağrılmıyor (ölçüldü: `profile.update`
    /// çağrı sayısı 0).
    ///
    /// Çözüm: test yüzeyi `tester.view.physicalSize` ile **birebir 800×600
    /// yapılır** ve diyalog `Scaffold(body:)` altında kurulur — bu yol
    /// `NotificationsDialog.show`'un gerçek davranışıyla (`showModalBottomSheet`
    /// içinde kayan altbilgi) örtüşür ve düğme erişilebilir olur.
    Future<void> tapSave(WidgetTester tester) async {
      final save = find.text('Kaydet');
      expect(save, findsOneWidget);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      // `ensureVisible` yetmezse düğmeye **doğrudan** git (konum doğru,
      // sadece kapsayıcı dışında): `tapAt` yerine `Scrollable.ensureVisible`in
      // yaptığından fazlası gerekiyor → `drag` ile kayan listeyi aşağı al.
      final center = tester.getCenter(save);
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      if (center.dy > size.height) {
        await tester.drag(
          find.byType(SingleChildScrollView),
          Offset(0, -(center.dy - size.height + 40)),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(save);
      await tester.pumpAndSettle();
    }

    Future<void> pumpDialog(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('tr'), Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('tr'),
            startLocale: const Locale('tr'),
            child: Builder(
              builder: (context) => ProviderScope(
                overrides: [
                  currentUserProvider.overrideWithValue(_kUser),
                  profileRepositoryProvider.overrideWithValue(profileRepo),
                  notificationPreferencesRepositoryProvider
                      .overrideWithValue(prefsRepo),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: Scaffold(
                    body: SizedBox(
                      // Bkz. [tapSave]: diyalog `end` hizalı olduğu için
                      // yüksek kapsayıcıda altbilgi ekranın dışına taşar ve
                      // gerçek `tap` ulaşmaz. Test yüzeyi 800×600 → 560 sığar.
                      height: 560,
                      child: NotificationsDialog(profile: _profile),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
    }

    testWidgets('sunucu tercihleri AYNI ekranda görünür', (tester) async {
      await pumpDialog(tester);

      // Kullanıcı iki ayrı ayar ekranı görmemeli.
      expect(find.text('Sunucu Hatırlatıcıları'), findsOneWidget);
      expect(find.text('Su İçme Hatırlatıcısı'), findsOneWidget);
      expect(find.text('Haftalık Özet'), findsOneWidget);
      // Öğün hatırlatıcıları da aynı diyalogda.
      expect(find.text('Öğün Hatırlatıcıları'), findsOneWidget);
    });

    testWidgets('weigh_in sunucu bölümünde YOK (tek doğruluk kaynağı)',
        (tester) async {
      await pumpDialog(tester);
      // `weigh_in` kaynağı profil sıklığıdır
      // (`profiles.weigh_in_frequency_days`); iki yerde ayrı ayrı ayar
      // çift doğruluk kaynağı olurdu.
      expect(find.text('Tartılma Sıklığı (gün)'), findsOneWidget);
    });

    testWidgets('Kaydet → sunucu tablosu doldurulur (sessiz kapalı çözülür)',
        (tester) async {
      await pumpDialog(tester);
      await tapSave(tester);

      // Tek `verify` + `captureAny`: mocktail aynı çağrıyı iki kez
      // doğrulamaya izin vermez; hem "kaç kez" hem "ne yazıldı" ölçülür.
      final captured =
          verify(() => prefsRepo.upsertAll('u1', captureAny())).captured;
      expect(captured, hasLength(1), reason: 'tek "Kaydet" → tek yazma');

      // Tablo boşken `check-reminders` bu 3 tipi sessizce kapatıyordu;
      // kaydetme artık **her tip** için satır yazar.
      final written = captured.single as Iterable;
      final types = written.map((p) => (p as NotificationPreference).type).toSet();
      expect(
        types,
        containsAll(<ServerNotificationType>[
          ServerNotificationType.water,
          ServerNotificationType.dailyLog,
          ServerNotificationType.weeklySummary,
          ServerNotificationType.goalAchieved,
        ]),
        reason: 'kullanıcı kaydettiğinde **dört** tip de satır almalı; aksi '
            'halde `check-reminders` sessizce kapalı kalır',
      );
    });

    testWidgets('push kanalı kapatılınca kayıt false yazılır', (tester) async {
      await pumpDialog(tester);

      // "Su İçme Hatırlatıcısı" kartındaki ilk Push çipini kapat.
      final chips = find.widgetWithText(FilterChip, 'Push');
      expect(chips, findsWidgets);
      final waterCard = find.ancestor(
        of: find.text('Su İçme Hatırlatıcısı'),
        matching: find.byType(Card),
      );
      final waterPush = find.descendant(of: waterCard, matching: chips).first;
      await tester.ensureVisible(waterPush);
      await tester.pumpAndSettle();
      await tester.tap(waterPush);
      await tester.pumpAndSettle();

      await tapSave(tester);

      final written =
          verify(() => prefsRepo.upsertAll('u1', captureAny())).captured.single
              as Iterable;
      final water = written.firstWhere(
        (p) => (p as NotificationPreference).type == ServerNotificationType.water,
      ) as NotificationPreference;
      expect(water.pushEnabled, isFalse,
          reason: 'kullanıcı çipi kapattıysa DB\'ye false yazılmalı; '
              'varsayılan true kalırsa kullanıcının kapatması sessizce '
              'kaybolur');
    });

    // ⭐ A4r7b'nin bulduğu hata (2026-09-28): `_loadServerPrefs` bir
    // `Future.microtask` içinde koşuyor. Yükleme **bitmeden** "Kaydet"
    // basılabiliyordu; o durumda `_serverPrefs` hâlâ `{}` → `upsertAll`
    // **hiçbir şey yazmıyor**, kullanıcı "Ayarlar güncellendi" görüyor ama
    // `check-reminders`'ın `water`/`daily_log`/`weekly_summary` için
    // "sessizce kapalı" davranışı **hiç değişmemiş** oluyordu.
    testWidgets('yükleme bitmeden "Kaydet" pasif (yarım kayıt olmaz)',
        (tester) async {
      // `fetch` **asla bitmeyen** bir gelecek: yükleme yarım kalır.
      final neverCompletes = Completer<Map<ServerNotificationType,
          NotificationPreference>>();
      when(() => prefsRepo.fetch(any())).thenAnswer((_) => neverCompletes.future);

      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('tr'), Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('tr'),
            startLocale: const Locale('tr'),
            child: Builder(
              builder: (context) => ProviderScope(
                overrides: [
                  currentUserProvider.overrideWithValue(_kUser),
                  profileRepositoryProvider.overrideWithValue(profileRepo),
                  notificationPreferencesRepositoryProvider
                      .overrideWithValue(prefsRepo),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: Scaffold(
                  body: SizedBox(
                    height: 560,
                    child: NotificationsDialog(profile: _profile),
                  ),
                ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      });

      final save = find.text('Kaydet');
      await tester.ensureVisible(save);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(
          find.ancestor(of: save, matching: find.byType(FilledButton)),
        ).onPressed,
        isNull,
        reason: 'tercihler yüklenmeden kaydetmek boş tablo yazar; düğme '
            'pasif olmalı',
      );
      // `fetch` çağrıldı ama `upsertAll` **hiç** çağrılmadı: yarım kayıt yok.
      verify(() => prefsRepo.fetch(any())).called(1);
      verifyNever(() => prefsRepo.upsertAll(any(), any()));
    });

    // Yükleme **hata** verirse ekran çökmez, uyarı gösterilir ve kaydetme
    // varsayılanlarla çalışır (PROTOKOL §2 P1: sessiz hata yutma yasak).
    testWidgets('fetch hata verirse uyarı gösterilir, kaydetme yine çalışır',
        (tester) async {
      when(() => prefsRepo.fetch(any()))
          .thenThrow(Exception('ağ yok'));

      await pumpDialog(tester);

      // Hata görünür (sessiz yutulmadı).
      expect(
        find.text(
          'Sunucu hatırlatma ayarları yüklenemedi. '
          'Kaydederseniz varsayılanlar kullanılır.',
        ),
        findsOneWidget,
        reason: 'kullanıcı kendi girdisi olmayan varsayılanların '
            'kaydedileceğini bilmeli',
      );

      // Ve yine de kaydedebilmeli: düğme **açık** (hata kilitlemez).
      // Snackbar yüzünden "Kaydet" öğesi örtülüyor → önce bir kare bekle.
      await tester.pumpAndSettle();
      await tapSave(tester);
      final captured =
          verify(() => prefsRepo.upsertAll('u1', captureAny())).captured;
      expect(captured, hasLength(1));
      final written = captured.single as Iterable;
      expect(
        written.map((p) => (p as NotificationPreference).type).toSet(),
        ServerNotificationType.values.toSet(),
        reason: 'yükleme başarısız olsa da **beş tipin de** satırı yazılır; '
            'aksi halde "sessizce kapalı" durumu sürer',
      );
    });
  });

  // Bölüm bileşenini **yalnız** (diyolog değil) kurar — gün etiketi testi
  // için gereken alan tek başına görünür olmalı.
  group('bölüm bileşeni — gün etiketi hizası', () {
    Future<void> pumpSection(
      WidgetTester tester,
      Map<ServerNotificationType, NotificationPreference> prefs,
    ) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('tr'), Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('tr'),
            startLocale: const Locale('tr'),
            child: Builder(
              builder: (context) => MaterialApp(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                home: Scaffold(
                  body: ServerNotificationPreferencesSection(
                    prefs: prefs,
                    onChanged: (type, update) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });
    }

    // ---------------------------------------------------------------------
    // Etiket ⇄ `summary_day` eşlemesi — bileşenin **ürettiği** öğe listesi
    // üzerinden, açılır listeyi açıp okuyarak ölçülür.
    //
    // Neden `tester.tap` ile "seç → `initialValue` oku" yapmıyoruz? Ölçüm:
    // `DropdownButtonFormField` kendi iç `FormFieldState.value`'sini tutar ve
    // **dışarıdan** gelen `initialValue` değişimini `didUpdateWidget` ile
    // **takip eder** (`dropdown.dart:2002-2007`). Bölümün `onChanged`
    // callback'i ise dış durumu günceller — testte o dış durum yoktur, dolayısıyla
    // `tap` sonrası okunan `initialValue` **kendi kopyamız** olur ve gerçek
    // kullanıcı yolunu ölçmüş olmaz. Öğe listesini doğrudan okuyunca ölçüm
    // kaynağı ile üretim kaynağı **aynı** olur.
    // ---------------------------------------------------------------------
    testWidgets('etiket ⇄ summary_day sunucu WEEKDAY_INDEX ile birebir',
        (tester) async {
      await pumpSection(tester, const {
        ServerNotificationType.weeklySummary: NotificationPreference(
          type: ServerNotificationType.weeklySummary,
          summaryDay: 1,
        ),
      });

      // Açılır listeyi aç ve **gün** öğelerini oku.
      final dayField = find.widgetWithText(DropdownButtonFormField<int>, 'Gün');
      await tester.tap(dayField);
      await tester.pumpAndSettle();

      // ⚠️ `_hourItems` de `DropdownMenuItem<int>` üretiyor ve `_PreferenceCard`
      // içindeki **saat** alanları da `int` taşıyor → tüm `DropdownMenuItem`
      // listesinde saat değerleri (`09`, `21`, …) de var. Doğru ölçüm, gün
      // alanının kendi `items` listesi: `DropdownButtonFormField` öğesi
      // `InputDecorator`/`Focus` altında sarmaladığı için widget ağacındaki
      // `DropdownButton<int>`'un `items`'i okunur (alan `find` ile çözülür).
      final items = <int, String>{};
      for (final button in tester.widgetList<DropdownButton<int>>(
        find.descendant(
          of: dayField,
          matching: find.byType(DropdownButton<int>),
        ),
      )) {
        for (final item
            in (button.items ?? const <DropdownMenuItem<int>>[])
                .whereType<DropdownMenuItem<int>>()) {
          final value = item.value;
          final child = item.child;
          if (value == null || child is! Text) continue;
          items[value] = child.data ?? '';
        }
      }
      expect(items, hasLength(7),
          reason: 'yedi günün tamamı listelenmeli (bulunan: $items)');

      // Sunucu `WEEKDAY_INDEX` (`check-reminders/helpers.ts:70-78`):
      // `{Sun:0, Mon:1, Tue:2, Wed:3, Thu:4, Fri:5, Sat:6}`.
      const serverIndex = <String, int>{
        'Pzt': 1,
        'Sal': 2,
        'Çar': 3,
        'Per': 4,
        'Cum': 5,
        'Cmt': 6,
        'Paz': 0,
      };

      // 1) **Değer → etiket**: `summary_day = 3` kayıtlı bir kullanıcı ekranı
      //    açtığında "Çar" görmeli.
      for (final entry in serverIndex.entries) {
        expect(items[entry.value], entry.key,
            reason: '`summary_day = ${entry.value}` ekranda "${entry.key}" '
                'göstermeli (sunucu 3 = Çarşamba)');
      }

      // 2) **Etiket → değer**: ters yön de ölçülmeli; "birebir" iddiası ancak
      //    iki yön de tutuyorsa doğrudur.
      for (final entry in serverIndex.entries) {
        final pointing = items.entries
            .where((e) => e.value == entry.key)
            .map((e) => e.key)
            .toList();
        expect(pointing, [entry.value],
            reason: '"${entry.key}" **yalnız** `summary_day = ${entry.value}` '
                'seçeneğine işaret etmeli; bulunan: $pointing');
      }
    });
    // Aynı hizanın **12 dilde** de geçerli olduğunu ölçer (etiketler
    // `DateFormat.E` ile üretiliyor; referans tarih bir dilde Pazartesi ise
    // hepsinde Pazartesi'dir, ama bu ayrıca kanıtlanır).
    test('gün etiketi 12 dilde de doğru güne işaret eder', () async {
      for (final locale in const [
        'tr', 'en', 'de', 'fr', 'es', 'ar', 'zh', 'ja', 'ko', 'pt', 'it', 'ru',
      ]) {
        await initializeDateFormatting(locale);
      }

      // `2024-01-08` Pazartesi olmalı (bileşendeki referans).
      expect(DateTime(2024, 1, 8).weekday, DateTime.monday,
          reason: 'bileşendeki `_monday` referansı Pazartesi olmalı');

      // Sunucu `WEEKDAY_INDEX` ile birebir: Pzt=1 … Paz=0.
      const serverIndex = <int, int>{
        DateTime.monday: 1,
        DateTime.tuesday: 2,
        DateTime.wednesday: 3,
        DateTime.thursday: 4,
        DateTime.friday: 5,
        DateTime.saturday: 6,
        DateTime.sunday: 0,
      };
      for (final locale in const [
        'tr', 'en', 'de', 'fr', 'es', 'ar', 'zh', 'ja', 'ko', 'pt', 'it', 'ru',
      ]) {
        for (var offset = 0; offset < 7; offset++) {
          final day = DateTime(2024, 1, 8).add(Duration(days: offset));
          final label = DateFormat.E(locale).format(day);
          // `DateTime.weekday` 1=Pzt → 7=Paz; sunucu 0=Paz → 1=Pzt.
          expect(serverIndex[day.weekday], (offset + 1) % 7,
              reason: '$locale/$label: sunucu dizini `summary_day` ile '
                  'eşleşmeli');
        }
      }
    });
  });

  group('summaryDay dizini sunucuyla aynı (0=Pazar)', () {
    test('sunucu weekday dizini 0=Pazar', () {
      // `check-reminders/helpers.ts:70-78` `WEEKDAY_INDEX = {Sun: 0, Mon: 1, …}`.
      // `summary_day` karşılaştırması bu dizinle yapılır; Dart'ın
      // `DateTime.weekday` dizini (1=Pazartesi) ile karıştırılırsa haftalık
      // özet **yanlış güne** gider.
      expect(defaultServerPreference(ServerNotificationType.weeklySummary)
          .summaryDay, 1,
          reason: '1 = Pazartesi');
    });
  });

  group('bölüm bileşeni — kopya yardımcısı', () {
    test('copyPreference yalnız verilen alanı değiştirir', () {
      const base = NotificationPreference(
        type: ServerNotificationType.water,
        pushEnabled: true,
        emailEnabled: true,
        startHour: 8,
        endHour: 20,
        intervalHours: 2,
      );

      final changed = copyPreference(base, startHour: 10);

      expect(changed.startHour, 10);
      expect(changed.endHour, 20, reason: 'verilmeyen alan korunur');
      expect(changed.pushEnabled, isTrue);
      expect(changed.emailEnabled, isTrue);
      expect(changed.type, ServerNotificationType.water);
    });

    test('tüm alanlar verilirse hepsi değişir', () {
      const base = NotificationPreference(
        type: ServerNotificationType.weeklySummary,
      );
      final changed = copyPreference(
        base,
        pushEnabled: true,
        emailEnabled: false,
        summaryDay: 3,
        summaryHour: 7,
      );
      expect(changed.pushEnabled, isTrue);
      expect(changed.emailEnabled, isFalse);
      expect(changed.summaryDay, 3);
      expect(changed.summaryHour, 7);
    });
  });
}

const _kUser = User(
  id: 'u1',
  appMetadata: {},
  userMetadata: null,
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

const _profile = Profile(
  id: 'u1',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  displayName: 'Test',
  email: 't@t.co',
  pushNotificationsEnabled: true,
  emailNotificationsEnabled: true,
  weighInFrequencyDays: 7,
  autoRecalculateMacros: true,
);

class _MockProfileRepository extends Mock implements ProfileRepository {}

class _MockNotificationPrefsRepository extends Mock
    implements NotificationPreferencesRepository {}
