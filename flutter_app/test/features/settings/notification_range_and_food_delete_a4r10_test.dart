/// A4r10 (Tur 11) — `weigh_in_frequency_days` aralık doğrulaması,
/// `goal_achieved` ölü tercih tipi, gece aralığı ve `deleteFood` arayüzü.
///
/// ## Bu test neden var?
///
/// A1r8'in migration'ı ölçülmüş bir ihlal bulmuştu:
/// `notifications_dialog.dart:146`
/// `'weigh_in_frequency_days': int.tryParse(_frequency.text.trim()) ?? 7`
/// → kullanıcı `0` yazdığında `profiles_weigh_in_frequency_days_range`
/// CHECK'i reddediyor, **`23514`** dönüyor ve **tek `try` içindeki tüm
/// `_save`** düşüyor — yani kullanıcı **profil + sunucu bildirim
/// tercihlerini** birlikte kaydedemiyordu. Negatif değer (`-5`) de
/// mümkündü ve `check-reminders/index.ts:293`'te **her koşuda**
/// tetikleniyordu.
///
/// A2r9 veri katmanına `validateUpdates` koydu; bu dosya **arayüz**
/// tarafının düzeltmesini ölçer (giriş sınırlama + hata mesajı + düğme
/// kapısı + sessiz `catch` yutmayı bırakma).
///
/// ## ⭐ Negatif kontrol notu (A4r7b'in tuzağı)
///
/// A4r7b `tester.tap('Kaydet')` çağrısının **sessizce hiçbir şey
/// yapmadığını** (`Offset(...) outside root Size(800,600)`) ölçmüştü —
/// 3 test yeşil görünürken `verify = 0`. Bu dosyada `_tapSave` önce
/// **kaydırır**, sonra `verify` ile **etkileşimin gerçekten gerçekleştiğini**
/// kanıtlar.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/models/food_item.dart';
import 'package:calorix/data/models/profile.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/food_repository.dart';
import 'package:calorix/data/repositories/notification_preferences_repository.dart';
import 'package:calorix/data/repositories/profile_repository.dart';
import 'package:calorix/features/settings/widgets/notifications_dialog.dart';
import 'package:calorix/features/settings/widgets/server_notification_preferences_section.dart';
import 'package:calorix/features/settings/widgets/weigh_in_frequency_input.dart';
import 'package:calorix/shared/widgets/delete_food_button.dart';

// ============================================================================
// 1) ⭐ weigh_in_frequency_days — GERÇEK CHECK sınırları
// ============================================================================

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  group('⭐ CHECK sınırları şemadan okundu, tahmin edilmedi', () {
    // Kaynak (okundu, kopyalanmadı):
    //   supabase/migrations/20260928400000_data_integrity_check_constraints.sql:225-228
    //   supabase/full_setup.sql:1013-1016
    //     CHECK (weigh_in_frequency_days IS NULL
    //            OR weigh_in_frequency_days BETWEEN 1 AND 365)
    test('alt sınır 1, üst sınır 365 (migration ile aynı)', () {
      expect(kWeighInMinDays, 1);
      expect(kWeighInMaxDays, 365);
      expect(kWeighInDefaultDays, 7, reason: 'kolon DEFAULT değeri');
    });

    test('arayüz sınırları A2r9 veri katmanıyla AYNI', () {
      // İki katman ayrışırsa kullanıcı arayüzde "geçerli" görür, DB reddeder
      // (A4r3'ün "iki istemci farklı sözleşme üretmesi" dersi).
      final dataLayer =
          ProfileRepository.fieldRanges['weigh_in_frequency_days'];
      expect(dataLayer, isNotNull);
      expect(dataLayer!.min, kWeighInMinDays);
      expect(dataLayer.max, kWeighInMaxDays);
    });
  });

  group('alt sınır / üst sınır / sınır değerleri', () {
    test('alt sınır (1) kabul', () {
      expect(parseWeighInFrequencyDays('1'), 1);
    });

    test('üst sınır (365) kabul', () {
      expect(parseWeighInFrequencyDays('365'), 365);
    });

    test('sınır değerlerinin ikisi de kabul', () {
      // `digitsOnly` + 3 hane: yazılabilir en büyük değer 365.
      for (final boundary in const [1, 7, 30, 100, 364, 365]) {
        expect(parseWeighInFrequencyDays('$boundary'), boundary,
            reason: '$boundary CHECK aralığında');
      }
    });

    test('alt sınırın bir altı (0) REDDEDİLİR — asıl ihlal', () {
      expect(parseWeighInFrequencyDays('0'), isNull,
          reason: 'CHECK `BETWEEN 1 AND 365` 0\'ı reddeder. Düzeltme öncesi '
              '`int.tryParse("0") ?? 7` → `0` gönderiliyordu ve `23514` '
              'tüm `_save`i düşürüyordu.');
    });

    test('negatif değerler REDDEDİLİR (check-reminders her koşuda tetikler)', () {
      for (final bad in const ['-1', '-5', '-365', '-1000']) {
        expect(parseWeighInFrequencyDays(bad), isNull,
            reason: 'negatif sıklık `daysSinceReminder >= $bad` '
                'karşılaştırmasında HER KOŞUDA doğrudur');
      }
    });

    test('üst sınırın bir üstü (366) REDDEDİLİR', () {
      expect(parseWeighInFrequencyDays('366'), isNull);
    });

    test('taşma değerler REDDEDİLİR', () {
      for (final bad in const ['1000', '9999', '99999']) {
        expect(parseWeighInFrequencyDays(bad), isNull);
      }
    });
  });

  group('geçersiz metin ve boş', () {
    test('harfli metin REDDEDİLİR', () {
      for (final bad in const ['abc', '7gun', 'x', '1a']) {
        expect(parseWeighInFrequencyDays(bad), isNull);
      }
    });

    test('ondalık REDDEDİLİR (kolon INTEGER)', () {
      // `7.5` → `int.tryParse` null döner; `7.0` de reddedilir çünkü
      // metin tam sayı **biçiminde değil**. İkisi de hata olmalı: sessizce
      // 7'ye yuvarlamak kullanıcının girdisini değiştirirdi.
      for (final bad in const ['7.5', '7.0', '1.9']) {
        expect(parseWeighInFrequencyDays(bad), isNull, reason: bad);
      }
    });

    test('bilimsel/ hexadecimal gösterim REDDEDİLİR', () {
      for (final bad in const ['1e3', '0x10', '7,0', '+7', '--7']) {
        expect(parseWeighInFrequencyDays(bad), isNull, reason: bad);
      }
    });

    test('boş metin → null (hata DEĞİL: NULL yazılır, CHECK `IS NULL OR`)', () {
      expect(parseWeighInFrequencyDays(''), isNull);
      expect(isBlankWeighInInput(''), isTrue);
      expect(isValidWeighInInput(''), isTrue,
          reason: 'boş alan hata değildir; `_save` `kWeighInDefaultDays` '
              '(7) yazar');
    });

    test('yalnız boşluk → boş sayılır', () {
      expect(parseWeighInFrequencyDays('   '), isNull);
      expect(isBlankWeighInInput('   '), isTrue);
    });

    test('null girdi geçersiz DEĞİL (alan henüz yüklenmedi)', () {
      expect(isValidWeighInInput(null), isTrue);
    });

    test('çevre boşlukları temizlenir (" 7 " → 7)', () {
      expect(parseWeighInFrequencyDays(' 7 '), 7);
      expect(isValidWeighInInput(' 30 '), isTrue);
    });
  });

  group('⭐ boş vs geçersiz ayrımı', () {
    // `parseWeighInFrequencyDays` ikisini de `null` döndürür; "Kaydet"
    // düğmesi **boş** alanı engellememeli, **geçersiz** metni engellemeli.
    test('isValidWeighInInput ayrımı doğru', () {
      expect(isValidWeighInInput(''), isTrue);
      expect(isValidWeighInInput('7'), isTrue);
      expect(isValidWeighInInput('0'), isFalse);
      expect(isValidWeighInInput('366'), isFalse);
      expect(isValidWeighInInput('abc'), isFalse);
    });
  });

  // =======================================================================
  // 2) ⭐ ARAYÜZ — gerçek "Kaydet" yolu
  // =======================================================================
  group('⭐ NotificationsDialog: 0 yazınca HİÇBİR ŞEY gönderilmiyor', () {
    testWidgets('"0" → profil ve sunucu tercihleri KAYDEDİLMEZ (yarım kayıt yok)',
        (tester) async {
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => profileRepo.update(any(), any()))
          .thenAnswer((_) async => null);
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
      when(() => prefsRepo.upsertAll(any(), any()))
          .thenAnswer((_) async {});

      await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);

      // Alanı `0` yap.
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.pumpAndSettle();

      // ⭐ Düzeltmenin kalıcı kanıtı: hata metni **görünür** oldu.
      expect(find.text('1-365 gün arasında bir değer girin'), findsOneWidget,
          reason: 'kullanıcı hangi alanın neden reddedildiğini görmeli');

      // "Kaydet" **pasif** → etkileşim gerçekleşmez.
      final saveButton = _saveButton(tester);
      final button = tester.widget<FilledButton>(
        find.ancestor(of: saveButton, matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull,
          reason: 'geçersiz değerde kaydetme düğmesi pasif olmalı — '
              'aksi halde CHECK reddi tüm `_save`i düşürür ve kullanıcı '
              'push/e-posta tercihlerini de kaybeder');

      // ⭐ Etkileşimin **gerçekten** denenip etkilenmediğini kanıtla:
      // düğmeye basmayı dene (A4r7b tuzağı: "yeşil test ≠ etkin test").
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      verifyNever(() => profileRepo.update(any(), any()));
      verifyNever(() => prefsRepo.upsertAll(any(), any()));
    });

    // ⚠️ Ayrı testler, ayrı `testWidgets` — diyalog tek `pumpWidget`
    // çağrısında kuruluyor ve `_save` `Navigator.pop` çağırıyor; aynı
    // testte ikinci kez kurmak boş `_history` ile çöküyor
    // (`'_history.isNotEmpty': is not true`). Ölçülen davranış, test
    // düzenlemesiyle **değişmedi**.
    testWidgets('alt sınır (1) kaydedilir', (tester) async {
      await _saveWith(tester, '1');
    });

    testWidgets('üst sınır (365) kaydedilir', (tester) async {
      await _saveWith(tester, '365');
    });

    testWidgets('sınır değeri (7) kaydedilir', (tester) async {
      await _saveWith(tester, '7');
    });

    testWidgets('boş alan → DB varsayılanı (7) yazılır', (tester) async {
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => profileRepo.update(any(), any()))
          .thenAnswer((_) async => null);
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
      when(() => prefsRepo.upsertAll(any(), any())).thenAnswer((_) async {});

      await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);
      await tester.enterText(find.byType(TextFormField), '');
      await tester.pumpAndSettle();

      await _tapSave(tester);

      final captured =
          verify(() => profileRepo.update('u1', captureAny())).captured;
      final updates = captured.single as Map<String, dynamic>;
      expect(updates['weigh_in_frequency_days'], kWeighInDefaultDays);
    });

    testWidgets('geçersiz → hatalı → düzeltilince KAYDEDİLEBİLİR',
        (tester) async {
      // Düzeltme "hata görünür ama kullanıcı çıkmazsa da" olmalı: alanı
      // düzelttikten sonra aynı ekrandan kaydedebilmeli.
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => profileRepo.update(any(), any()))
          .thenAnswer((_) async => null);
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
      when(() => prefsRepo.upsertAll(any(), any())).thenAnswer((_) async {});

      await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);
      await tester.enterText(find.byType(TextFormField), '0');
      await tester.pumpAndSettle();
      expect(find.text('1-365 gün arasında bir değer girin'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '14');
      await tester.pumpAndSettle();
      expect(find.text('1-365 gün arasında bir değer girin'), findsNothing);

      await _tapSave(tester);
      final captured =
          verify(() => profileRepo.update('u1', captureAny())).captured;
      expect((captured.single as Map)['weigh_in_frequency_days'], 14);
    });

    testWidgets('geçersiz yazılırken sunucu tercihleri de ETKİLENMEZ',
        (tester) async {
      // Asıl P1 etkisi: `_save` iki yazma yolunu kapsıyordu. Geçersiz
      // değerde **hiçbiri** çalışmamalı (yarım kayıt yok) — ama bir sonraki
      // geçerli kayıtta **ikisi de** gitmeli.
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => profileRepo.update(any(), any()))
          .thenAnswer((_) async => null);
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
      when(() => prefsRepo.upsertAll(any(), any())).thenAnswer((_) async {});

      await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);
      await tester.enterText(find.byType(TextFormField), '999');
      await tester.pumpAndSettle();
      await tester.tap(_saveButton(tester), warnIfMissed: false);
      await tester.pumpAndSettle();
      verifyNever(() => profileRepo.update(any(), any()));
      verifyNever(() => prefsRepo.upsertAll(any(), any()));

      await tester.enterText(find.byType(TextFormField), '21');
      await tester.pumpAndSettle();
      await _tapSave(tester);
      verify(() => profileRepo.update('u1', any())).called(1);
      verify(() => prefsRepo.upsertAll('u1', any())).called(1);
    });

    testWidgets('ProfileFieldRangeError ayrı yakalanır (sessiz yutma yok)',
        (tester) async {
      // A2r9'ın veri katmanı savunması buraya ulaşırsa kullanıcı **ne
      // yapması gerektiğini** öğrenmeli — genel "Kaydedilemedi" yetersiz.
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => profileRepo.fetch(any())).thenAnswer((_) async => null);
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
      when(() => profileRepo.update(any(), any())).thenThrow(
            const ProfileFieldRangeError(
              field: 'weigh_in_frequency_days',
              value: 0,
              range: '1-365 gün',
              reason: 'aralık dışı',
            ),
          );

      await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);
      await _tapSave(tester);

      // Mesaj **iki** yerde görünür: alanın `errorText`'inde ve
      // `SnackBar`'da. İkisi de kasıtlı (biri kalıcı, biri geçici).
      expect(
        find.text('1-365 gün arasında bir değer girin'),
        findsNWidgets(2),
        reason: 'aralık hatası kullanıcıya alan aralığıyla bildirilir',
      );
      // Sunucu tercihleri **yazılmadı** (yarım kayıt yok): profil hatası
      // ikinci yazma yoluna ulaşmadan `catch`'e düşer.
      verifyNever(() => prefsRepo.upsertAll(any(), any()));
      // Genel "Kaydedilemedi" mesajı **gösterilmedi** — A2r9'ın hata tipi
      // özel bir davranışa sahip olmalı (sessiz yutma değil, *anlamsız*
      // hata da değil).
      expect(find.textContaining('Kaydedilemedi'), findsNothing);
    });
  });

  // =======================================================================
  // 3) ⭐ goal_achieved ölü tercih tipi → UI'dan gizlendi
  // =======================================================================
  group('⭐ goal_achieved UI\'da GÖSTERİLMİYOR (ürün kararı 2-B)', () {
    testWidgets('ekranda "Hedef Başarısı" kartı yok', (tester) async {
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});

      await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);

      // Ölçüm gerekçesi: `check-reminders/index.ts` bu tipi **hiç okumuyor`
      // (dört blok: weigh_in :287, water :346, daily_log :410,
      // weekly_summary :464) ve `send-notification`'ı çağıran dört çağrı da
      // bu dört tipi gönderiyor. Kullanıcı anahtarı görüp hiçbir şey
      // olmamasını beklemez.
      expect(find.text('Hedef Başarısı'), findsNothing);
    });

    testWidgets('kalan üç tip hâlâ görünüyor', (tester) async {
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});

      await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);

      expect(find.text('Su İçme Hatırlatıcısı'), findsOneWidget);
      expect(find.text('Günlük Kayıt Hatırlatıcısı'), findsOneWidget);
      expect(find.text('Haftalık Özet'), findsOneWidget);
    });
  });

  // =======================================================================
  // 4) ⭐ Gece aralığı (21 → 09) arayüzden yazılamaz
  // =======================================================================
  group('⭐ gece aralığı arayüzden seçilemez (sunucu desteklemiyor)', () {
    test('sunucu koşulu start > end için HİÇBİR saatte sağlanmaz', () {
      // `check-reminders/index.ts:356`:
      //   normalizedHour >= startHour && normalizedHour <= endHour
      // 21→09: hiçbir `h` için `h >= 21 && h <= 9` doğru değildir.
      bool serverSends(int hour, int start, int end) =>
          hour >= start && hour <= end;

      expect(serverSends(21, 21, 9), isFalse);
      expect(serverSends(9, 21, 9), isFalse);
      expect(serverSends(0, 21, 9), isFalse);
      // Karşılaştırma: gündüz aralığı **çalışır** → sunucu mantığı sağlam,
      // yalnız gece aralığı temsil edilemiyor.
      for (var h = 9; h <= 21; h++) {
        expect(serverSends(h, 9, 21), isTrue, reason: '09→21 saat $h çalışır');
      }
    });

    test('bitiş saati seçenekleri start\'tan küçük saatleri İÇERMEZ', () {
      // Saf liste ölçümü. Menü **tembel** (lazy) kurulduğu için
      // `find.text('08')` yalnız **görünen** öğeleri yakalar ve
      // "listede yok" iddiası kanıtlamaz (A4r7b'in dersi).
      //
      // Varsayılan `water.startHour = 9` → 00..08 **sunulamaz**.
      expect(endHourOptions(9), equals([for (var h = 9; h <= 23; h++) h]));
      expect(endHourOptions(9), isNot(contains(8)));
      expect(endHourOptions(9), isNot(contains(0)));
    });

    test('endHourOptions her start için start..23 aralığını verir', () {
      for (var start = 0; start <= 23; start++) {
        final options = endHourOptions(start);
        expect(options.first, start);
        expect(options.last, 23);
        expect(options.length, 24 - start);
        // ⭐ Sözleşme: `start > end` **hiçbir seçenek çiftinde** oluşamaz.
        for (final end in options) {
          expect(end, greaterThanOrEqualTo(start),
              reason: 'start=$start end=$end → check-reminders koşulu '
                  'hiçbir saatte sağlanmaz');
        }
      }
    });

    test('21:00 → 09:00 gibi bir gece aralığı SEÇİLEMEZ', () {
      // start = 21 iken 09 listede **yok** → gece aralığı arayüzden
      // yazılamaz. Kullanıcı 21:00–23:00 arasını seçebilir (tek akşam
      // dilimi) ama 09:00'a **uzatamaz**.
      expect(endHourOptions(21), equals([21, 22, 23]));
      expect(endHourOptions(21), isNot(contains(9)));
    });

    test('aralık dışı start değeri (DB bozuk satırı) çökertmez', () {
      // `fromRow` `_asInt` ile güvenli değer üretir ama veri katmanı
      // `clamp` da uygular; savunma derinliği için `endHourOptions`
      // **kendi** sınırını koyar: 30 → 23, -5 → 0.
      expect(endHourOptions(30), equals([23]));
      expect(endHourOptions(-5).first, 0);
    });

    testWidgets('su bölümü varsayılanı 09→21 (gece değil)', (tester) async {
      final profileRepo = _MockProfileRepository();
      final prefsRepo = _MockNotificationPrefsRepository();
      when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});

      await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);

      // `defaultServerPreference(water)` = start 9, end 21 → **gece değil**.
      // Doğrulama mesajı ekranda görünür olmalı.
      expect(find.text('Su İçme Hatırlatıcısı'), findsOneWidget);
      expect(
        find.text(
          'Bitiş saati başlangıçtan önce olamaz (gece aralığı desteklenmiyor).',
        ),
        findsOneWidget,
        reason: 'kısıt sessiz olmamalı — kullanıcı nedenini bilmeli',
      );
    });
  });

  // =======================================================================
  // 5) ⭐ deleteFood arayüzü
  // =======================================================================
  group('⭐ DeleteFoodButton — onay akışı', () {
    late _MockFoodRepository repo;

    setUp(() {
      repo = _MockFoodRepository();
      when(() => repo.deleteFood(any(), any())).thenAnswer((_) async => true);
    });

    Future<void> pump(
      WidgetTester tester, {
      required FoodItem food,
    }) async {
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
                  foodRepositoryProvider.overrideWithValue(repo),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: Scaffold(
                    body: Center(
                      child: DeleteFoodButton(food: food),
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

    testWidgets('custom girdide (foodId null) düğme GİZLENİR', (tester) async {
      await pump(
        tester,
        food: const FoodItem(
          id: 'custom_1',
          name: 'Ev yapımı köfte',
          calories: 250,
          proteinG: 20,
          carbsG: 5,
          fatG: 15,
          isCustom: true,
        ),
      );
      expect(find.byType(IconButton), findsNothing,
          reason: '`foods` tablosunda satır yok → silinecek kayıt yok');
    });

    testWidgets(
        '⭐ A4r11: topluluk/seed gıdasında (canDelete=false) düğme GİZLENİR',
        (tester) async {
      await pump(
        tester,
        food: const FoodItem(
          id: 'seed-1',
          foodId: 'seed-1',
          name: 'Mercimek Çorbası',
          calories: 90,
          proteinG: 4,
          carbsG: 12,
          fatG: 1,
          canDelete: false,
        ),
      );
      expect(find.byType(IconButton), findsNothing,
          reason:
              '`created_by IS NULL` → RLS DELETE reddi → düğme boşuna umut verir');
      expect(find.byTooltip('Yemek sil: Mercimek Çorbası'), findsNothing);
    });

    testWidgets('tooltip + Semantics (ikon-only düğme kuralı)', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        food: const FoodItem(
          id: 'f1',
          foodId: 'f1',
          canDelete: true,
          name: 'Yoğurt',
          calories: 60,
          proteinG: 5,
          carbsG: 4,
          fatG: 2,
        ),
      );

      expect(find.byTooltip('Yemek sil: Yoğurt'), findsOneWidget,
          reason: 'proje kuralı: ikon-only düğmede tooltip şart');

      final node = tester.getSemantics(find.byType(IconButton));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.tooltip, contains('Yemek sil'));
      handle.dispose();
    });

    testWidgets('dokunmadan önce dialog açılmaz; iptal = silme YOK',
        (tester) async {
      await pump(
        tester,
        food: const FoodItem(
          id: 'f1',
          foodId: 'f1',
          canDelete: true,
          name: 'Yoğurt',
          calories: 60,
          proteinG: 5,
          carbsG: 4,
          fatG: 2,
        ),
      );

      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Dialog üç bilgiyi birlikte gösterir.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Yemek silinsin mi?'), findsOneWidget);
      expect(find.text('Yoğurt'), findsWidgets,
          reason: 'hangi kaydın silineceği belli olmalı');
      expect(find.text('Bu yemek favorilerinizden de silinecek.'), findsOneWidget,
          reason: 'favori kaybı **sessiz** olmamalı');

      // İptal.
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      verifyNever(() => repo.deleteFood(any(), any()));
    });

    testWidgets('onaylayınca deleteFood çağrılır + "silindi" mesajı',
        (tester) async {
      await pump(
        tester,
        food: const FoodItem(
          id: 'f1',
          foodId: 'f1',
          canDelete: true,
          name: 'Yoğurt',
          calories: 60,
          proteinG: 5,
          carbsG: 4,
          fatG: 2,
          useCount: 3,
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // Kullanım sayısı gösterilir (favoriler/sık kullanılanlar bölümlerinde
      // `useCount` doludur).
      expect(find.text('Bu yemek 3 öğünde kullanıldı.'), findsOneWidget);

      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      // ⭐ Etkileşim gerçekten gerçekleşti: RLS filtresi doğru kullanıcıyla.
      verify(() => repo.deleteFood('u1', 'f1')).called(1);
      expect(find.text('Yemek silindi'), findsOneWidget);
    });

    testWidgets('deleteFood false dönerse "başarı" YANLIŞ SÖYLENMEZ',
        (tester) async {
      when(() => repo.deleteFood(any(), any())).thenAnswer((_) async => false);
      await pump(
        tester,
        food: const FoodItem(
          id: 'f1',
          foodId: 'f1',
          canDelete: true,
          name: 'Yoğurt',
          calories: 60,
          proteinG: 5,
          carbsG: 4,
          fatG: 2,
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.text('Yemek silindi'), findsNothing,
          reason: '`false` = silinmedi (RLS ya da meal_entries FK 23503)');
      expect(
        find.text(
          'Yemek silinemedi. Bir öğünde kullanılıyorsa önce o kaydı silin.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('deleteFood fırlatırsa hata gösterilir (sessiz yutma yok)',
        (tester) async {
      when(() => repo.deleteFood(any(), any()))
          .thenThrow(Exception('ağ yok'));
      await pump(
        tester,
        food: const FoodItem(
          id: 'f1',
          foodId: 'f1',
          canDelete: true,
          name: 'Yoğurt',
          calories: 60,
          proteinG: 5,
          carbsG: 4,
          fatG: 2,
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sil'));
      await tester.pumpAndSettle();

      expect(find.text('Yemek silindi'), findsNothing);
      expect(
        find.text(
          'Yemek silinemedi. Bir öğünde kullanılıyorsa önce o kaydı silin.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('oturum yoksa silme denemesi yapılmaz', (tester) async {
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
                  currentUserProvider.overrideWithValue(null),
                  foodRepositoryProvider.overrideWithValue(repo),
                ],
                child: MaterialApp(
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  locale: context.locale,
                  home: const Scaffold(
                    body: DeleteFoodButton(
                      food: FoodItem(
                        id: 'f1',
                        foodId: 'f1',
                        canDelete: true,
                        name: 'Yoğurt',
                        calories: 60,
                        proteinG: 5,
                        carbsG: 4,
                        fatG: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      });

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      // RLS `auth.uid()` null iken DELETE reddedilir → sunucuya hiç gitmemeli.
      expect(find.byType(AlertDialog), findsNothing);
      verifyNever(() => repo.deleteFood(any(), any()));
    });
  });
}

// ============================================================================
// Yardımcılar
// ============================================================================

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

Future<void> _pumpDialog(
  WidgetTester tester, {
  required _MockProfileRepository profileRepo,
  required _MockNotificationPrefsRepository prefsRepo,
}) async {
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
}

Finder _saveButton(WidgetTester tester) => find.text('Kaydet');

/// Değeri yazar, "Kaydet"e basar ve **gönderilen sayının** bu değer
/// olduğunu doğrular (`clamp` sessiz veri bozulması olurdu).
Future<void> _saveWith(WidgetTester tester, String value) async {
  final profileRepo = _MockProfileRepository();
  final prefsRepo = _MockNotificationPrefsRepository();
  when(() => profileRepo.update(any(), any())).thenAnswer((_) async => null);
  when(() => prefsRepo.fetch(any())).thenAnswer((_) async => {});
  when(() => prefsRepo.upsertAll(any(), any())).thenAnswer((_) async {});

  await _pumpDialog(tester, profileRepo: profileRepo, prefsRepo: prefsRepo);
  await tester.enterText(find.byType(TextFormField), value);
  await tester.pumpAndSettle();

  expect(find.text('1-365 gün arasında bir değer girin'), findsNothing,
      reason: '$value aralıkta, hata gösterilmemeli');
  await _tapSave(tester);

  final captured =
      verify(() => profileRepo.update('u1', captureAny())).captured;
  final updates = captured.single as Map<String, dynamic>;
  expect(updates['weigh_in_frequency_days'], int.parse(value),
      reason: 'kullanıcının girdiği değer **aynen** yazılmalı');
}

/// "Kaydet"e **gerçekten** basar.
///
/// ⚠️ A4r7b'in tuzağı: `tester.tap` konum ekran dışındaysa **sessizce**
/// hiçbir şey yapmıyor ve test **yeşil** görünür. Bu yardımcı önce kaydırır.
Future<void> _tapSave(WidgetTester tester) async {
  final save = _saveButton(tester);
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

class _MockFoodRepository extends Mock implements FoodRepository {}
