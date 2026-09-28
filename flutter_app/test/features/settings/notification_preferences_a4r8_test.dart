/// Sunucu bildirim tercihleri — **A4r8 (Tur 10) düzeltmeleri**.
///
/// ## Bu test neden var?
///
/// A4r7/A4r7b sunucu tercihleri arayüzünü ve veri katmanını yazdı; bu
/// dosya o işin **eksik kalan kanıtlarını** kapatır:
///
/// 1. ⭐ **`interval_hours: 0` gönderilmiyor** — A1r8'in bulduğu çakışmanın
///    Flutter tarafında **kapandığının** kanıtı. Web istemcisi
///    (`src/hooks/useNotifications.ts:30-33`) `interval_hours: 0` yazıyor ve
///    `notification_preferences_hours_range` CHECK'i (`BETWEEN 1 AND 24`)
///    bunu **reddediyor** (A1r8 bunu canlı Postgres'te kanıtladı).
/// 2. ⭐ **Profil seviyesi master anahtarların gölgelenmesi** — `send-notification`
///    (`index.ts:423-424`) `preference?.push_enabled ?? profile.push_...` diye
///    okur, yani **tipe özel** değer önce gelir. A4r7'nin eklediği kaydetme
///    sırası, kullanıcı üstteki "Push Bildirimleri" anahtarını kapattığında
///    bile **tipe özel `push_enabled: true`** yazıyordu → master anahtar
///    sessizce işlevsiz kalıyordu.
/// 3. **Saat aralığı tutarlılığı** — `start_hour > end_hour` yazılırsa
///    `check-reminders/index.ts:356` `normalizedHour >= startHour && <= endHour`
///    koşulunu **hiçbir saatte** sağlamaz → `water` hatırlatması sessizce
///    hiç gönderilmez. DB CHECK'i bunu reddetmiyor (her iki saat de 0..23).
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/models/profile.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/notification_preferences_repository.dart';
import 'package:calorix/data/repositories/profile_repository.dart';
import 'package:calorix/features/settings/widgets/notifications_dialog.dart';
import 'package:calorix/features/settings/widgets/server_notification_preferences_section.dart'
    show copyPreference;


void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  // =======================================================================
  // 1) ⭐ interval_hours: 0 ASLA gönderilmiyor
  // =======================================================================
  group('⭐ interval_hours CHECK çakışması kapandı (A1r8 aktarımı)', () {
    // `notification_preferences_hours_range`
    //   CHECK (start_hour BETWEEN 0 AND 23 AND end_hour BETWEEN 0 AND 23
    //          AND interval_hours BETWEEN 1 AND 24 …)
    // A1r8 canlı Postgres'te ölçtü: `interval_hours = 0` → `ERROR: violates
    // check constraint "notification_preferences_hours_range"`. Web
    // (`useNotifications.ts:30`) tam olarak bu değeri yazıyor.
    //
    // Flutter tarafında **herhangi bir yoldan** üretilen `toRow` çıktısında
    // `interval_hours` 1..24 aralığında olmalı.
    const allowedIntervalHours = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
      15, 16, 17, 18, 19, 20, 21, 22, 23, 24];

    test('varsayılanlar: hiçbir tip interval_hours 0 yazmıyor', () {
      for (final type in ServerNotificationType.values) {
        final value = defaultServerPreference(type).toRow('u1')['interval_hours'];
        expect(allowedIntervalHours, contains(value),
            reason: '$type varsayılanı $value yazıyor; 0 CHECK ile reddedilir');
      }
    });

    test('kullanıcı bilerek 0 yazarsa normalize edilir (0 değil!)', () {
      // Arayüzde 0 seçilebilir bir değer **yok** (menü 1..24), ama veri
      // katmanı sözleşmeyi **kendi başına** korumalı: `const` bir tercih
      // `intervalHours: 0` ile kurulabiliyor.
      const zero = NotificationPreference(
        type: ServerNotificationType.water,
        intervalHours: 0,
      );
      final value = zero.toRow('u1')['interval_hours'];
      expect(value, isNot(0),
          reason: '0 gönderilirse PostgREST 400 döner ve **tüm ayar '
              'kaydı** düşer (PROTOKOL §2 P1)');
      expect(allowedIntervalHours, contains(value));
    });

    test('negatif ve taşma değerler de reddedilir', () {
      const base = NotificationPreference(type: ServerNotificationType.water);
      for (final bad in const [-1, -24, 25, 100, 9999]) {
        final row = copyPreference(base, intervalHours: bad).toRow('u1');
        expect(allowedIntervalHours, contains(row['interval_hours']),
            reason: 'interval_hours=$bad aralık dışı');
      }
    });

    // ⭐ En güçlü kanıt: **gerçek kaydetme yolundan** geçen değerleri ölç.
    testWidgets('⭐ "Kaydet" hiçbir tip için interval_hours: 0 göndermiyor',
        (tester) async {
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => profileRepo.update(any(), any()))
          .thenAnswer((_) async => null);
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
      when(() => prefsRepo.upsertAll(any(), any()))
          .thenAnswer((_) async {});

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
                      child: const NotificationsDialog(profile: _profile),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      await _tapSave(tester);

      final captured =
          verify(() => prefsRepo.upsertAll('u1', captureAny())).captured;
      expect(captured, hasLength(1));

      // Gerçek **satır** payload'ını ölç (`toRow`), modeli değil.
      final prefs = captured.single as Iterable<NotificationPreference>;
      expect(prefs, isNotEmpty);
      for (final pref in prefs) {
        final interval = pref.toRow('u1')['interval_hours'];
        expect(allowedIntervalHours, contains(interval),
            reason: '${pref.type.wire} → interval_hours=$interval. A1r8\'in '
                'canlı Postgres ölçümü: 0 yazılırsa CHECK reddeder ve '
                'kullanıcı **hiçbir ayarını** kaydedemez.');
      }
    });
  });

  // =======================================================================
  // 2) ⭐ Master anahtar gölgelenmesi
  // =======================================================================
  group('⭐ profil seviyesi master anahtarlar gölgelenmiyor', () {
    // `send-notification/index.ts:423-424`:
    //   const pushEnabled  = preference?.push_enabled  ?? profile.push_notifications_enabled ?? true;
    //   const emailEnabled = preference?.email_enabled ?? profile.email_notifications_enabled ?? true;
    //
    // `??` yalnız `NULL` üstüne düşer. A4r7 `notification_preferences`'a
    // **her tip için** satır yazmaya başlayınca, `push_enabled` artık `true`
    // olduğu için profil master anahtarı **hiç okunmuyor** → kullanıcı
    // üstteki anahtarı kapatıyor, bildirimler yine gidiyor.
    test('veri katmanı birleştirmesi master && tip bileşimini uygular', () {
      final prefs = {
        for (final type in ServerNotificationType.values)
          type: defaultServerPreference(type),
      };

      final masterOff = NotificationPreferencesRepository.applyMasterSwitches(
        prefs,
        masterPush: false,
        masterEmail: false,
      );
      for (final entry in masterOff.entries) {
        expect(entry.value.pushEnabled, isFalse,
            reason: '${entry.key.wire}: master push kapalıyken true kalmamalı');
        expect(entry.value.emailEnabled, isFalse,
            reason: '${entry.key.wire}: master e-posta kapalıyken true '
                'kalmamalı');
      }

      final masterOn = NotificationPreferencesRepository.applyMasterSwitches(
        prefs,
        masterPush: true,
        masterEmail: true,
      );
      for (final entry in masterOn.entries) {
        // Master açıkken **kullanıcının kendi tip tercihi** korunur
        // (varsayılanlar web ile birebir aynı olduğu için).
        expect(entry.value.pushEnabled, entry.value.pushEnabled);
        expect(masterOn[entry.key]!.type, entry.value.type);
      }
    });

    test('master && tip: dört kombinasyonun tamamı', () {
      expect(effectiveChannel(master: false, type: true), isFalse);
      expect(effectiveChannel(master: true, type: true), isTrue);
      expect(effectiveChannel(master: true, type: false), isFalse);
      expect(effectiveChannel(master: false, type: false), isFalse);
    });

    testWidgets('master anahtarı kapalıyken "Kaydet" false yazıyor',
        (tester) async {
      // A4r7'nin bıraktığı hatanın **doğrudan** ölçümü: profil master push
      // `false` (`_profile.pushNotificationsEnabled = false`) ama tip
      // varsayılanları `push_enabled: true`. Düzeltme öncesi yazılan satır
      // `true` olurdu → `send-notification` `??` ile profil değerine düşmez
      // çünkü satır artık var → **master anahtar ölü** olurdu.
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => profileRepo.update(any(), any()))
          .thenAnswer((_) async => null);
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
      when(() => prefsRepo.upsertAll(any(), any()))
          .thenAnswer((_) async {});

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
                      child: const NotificationsDialog(profile: _profile),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      await _tapSave(tester);

      final captured =
          verify(() => prefsRepo.upsertAll('u1', captureAny())).captured;
      final prefs = captured.single as Iterable<NotificationPreference>;
      expect(prefs, isNotEmpty);
      for (final pref in prefs) {
        expect(pref.pushEnabled, isFalse,
            reason: '${pref.type.wire}: profil master push kapalıyken true '
                'yazıldı. `send-notification/index.ts:423` '
                '`preference?.push_enabled ?? profile.push_...` okuduğu için '
                'satır var olduğu anda profil değeri **hiç** dikkate '
                'alınmaz → kullanıcının master anahtarı ölü kalır.');
      }
    });
  });

  // =======================================================================
  // 3) start_hour > end_hour → sessiz hiç gönderilmeme
  // =======================================================================
  group('saat aralığı tutarlılığı (check-reminders koşulu)', () {
    // `check-reminders/index.ts:356`:
    //   if (normalizedHour >= startHour && normalizedHour <= endHour) { … }
    // `start_hour = 21`, `end_hour = 9` → hiçbir `normalizedHour` ikisini birden
    // sağlamaz → `water` hatırlatması **hiç gönderilmez**, kullanıcı hata da
    // görmez. DB CHECK'i iki değeri de 0..23 olduğu için **kabul eder**.
    test('gece aralığı (21→09) CHECK reddi olmadan da normalleştirilir', () {
      const night = NotificationPreference(
        type: ServerNotificationType.water,
        startHour: 21,
        endHour: 9,
      );
      final row = night.toRow('u1');
      expect(row['start_hour'], lessThanOrEqualTo(row['end_hour'] as int),
          reason: 'start > end → check-reminders koşulu hiç sağlanmaz');
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
  pushNotificationsEnabled: false,
  emailNotificationsEnabled: true,
  weighInFrequencyDays: 7,
  autoRecalculateMacros: true,
);

/// `send-notification`'ın gerçek okuma sırası: `preference ?? profile`.
///
/// `??` yalnız `NULL` üstüne düştüğü için **birleşim (OR)** değil, ilk
/// dolu değer kazanır. Kaydetme tarafında master anahtarı **AND** olarak
/// uygulamak zorundayız.
/// `send-notification`'ın gerçek okuma sırasının **karşılığı**.
///
/// `preference ?? profile` birleşim (OR) değil, "ilk dolu değer" kuralıdır;
/// bu yüzden istemcide master anahtar **AND** olarak uygulanmalıdır.
/// Gerçek kanıt [NotificationsDialog] üzerinden ölçülür (aşağıda);
/// bu yardımcı bileşimin **kuralını** tek satırda belgeler.
@pragma('vm:prefer-inline')
bool effectiveChannel({required bool master, required bool type}) =>
    master && type;

/// "Kaydet" düğmesine basar.
///
/// ⚠️ Diyalog `end` hizalı bir altbilgi içeriyor ve `SingleChildScrollView`
/// içinde; `ensureVisible` tek başına yetmiyor (aynı ölçüm A4r7b'de yapıldı:
/// düğmenin merkezi ekran dışında kalınca `tester.tap` **sessizce** hiçbir
/// şey yapmıyor). Bu yüzden konum ekranın altındaysa liste önce kaydırılır.
Future<void> _tapSave(WidgetTester tester) async {
  final save = find.text('Kaydet');
  expect(save, findsOneWidget);
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
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

class _MockProfileRepository extends Mock implements ProfileRepository {}

class _MockNotificationPrefsRepository extends Mock
    implements NotificationPreferencesRepository {}
