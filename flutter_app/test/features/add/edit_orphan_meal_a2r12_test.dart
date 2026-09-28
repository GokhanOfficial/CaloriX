/// ⭐ A2r12 (Tur 12) — **Görev 3**: gıda silindikten sonra öğün düzenleme
/// (göçü) ölçüldü ve düzeltildi.
///
/// ## Ölçülen durum (brifteki varsayım)
/// *"gıda silinince `custom_name` korunuyor. Peki sonra kullanıcı o öğünü
/// düzenlerse? `edit_meal_entry_dialog` gıda seçili değil, öğün güncelleniyor
/// mu? Silme sonrası bozuk kayıt kalmıyor mu?"*
///
/// ### Ölçüm (geçici prob testiyle, sonra SİLİNDİ)
///
/// ```text
/// PROBE displayName = "Bilinmeyen"
/// PROBE customName = null
/// PROBE foodId     = null
/// PROBE dialog name seed = ""          ← boş ad alanı
/// PROBE save button enabled = false    ← Kaydet KAPALI
/// PROBE after typing, save enabled = true
/// PROBE updateMealEntry CALLED … updates={custom_name: Yoğurt, …}
/// ```
///
/// ### ⭐ Gerçek bulgu: iki ayrı yol
///
/// **1) `custom_name` doluysa** (A4r11'in yazdığı `canDelete` gıdası) →
/// sorun **yok**: dialog adı gösterir, Kaydet açılır, `custom_name` korunur.
/// `meal_entries`in `source/food_id` alanları `updateMealEntry`'de
/// **kısmi güncelleme** ile korunur (`edit_meal_entry_dialog.dart:143`) →
/// yani `food_id` NULL iken de kayıt bozulmaz.
///
/// **2) `custom_name` boşsa** (`add_from_food_dialog:109` yalnız
/// `isCustom || canDelete` için ad yazar → **topluluk/seed** gıdasından
/// eklenen her öğünde `custom_name` NULL) → gerçek kusur:
///
/// - Dashboard'da satır **"Bilinmeyen"** (`meal_entry.dart:89`).
/// - Kullanıcı öğünü açtığında **boş** ad alanı, **kapalı** Kaydet düğmesi.
/// - Ekranda hangi yemeği düzenlediğine dair **hiçbir ipucu yok**.
/// - Kaydetmek için kullanıcı adı **elle yazmak** zorunda; kaloriler
///   ekranda **100g** olarak göründüğü için yazdığı ad büyük ihtimalle
///   gıdanın gerçek adı olmaz.
///
/// Bu bir **P1**'dir (kullanıcıyı yanlış kayda yönlendiren UI + veri
/// kalitesini sessizce düşüren akış), "veri kaybı" değildir — kayıt duruyor.
///
/// ## Düzeltme
///
/// `_seedName`: `custom_name` boşsa `MealEntry.displayName` seed edilir ve
/// alanın altında `dialogs.edit.nameMissing` ipucu gösterilir. `displayName`
/// zaten `"Bilinmeyen"` ise (gerçek ad yok) boş bırakılır — `"Bilinmeyen"`
/// adını yazdırmak veri uydurmak olurdu.
///
/// ## ⭐ "Yeşil test ≠ etkin test" — bu dosyadaki tuzak (A2r12, 6. vaka)
///
/// İlk ölçüm denemesinde test "yeşil" göründü ama `updateMealEntry` **hiç
/// çağrılmıyordu** (`verify = 0`) ve test yine de geçiyordu. İki ayrı tuzak
/// üst üste geldi:
///
/// 1. **`tester.tap` düğmeye ulaşmıyordu.** `getCenter` +
///    `hitTestOnBinding` **ulaşıyordu** (A4r10'ın tuzağı tam olarak bu) ama
///    `_save` **async**; `pumpAndSettle` sahte async kuyruğu **dışında**
///    kalan `Future`'ı bitirmiyor. Çözüm: `tester.runAsync(() => Future
///    .delayed(...))` + `pumpAndSettle`.
/// 2. **`verify()` eşleşmezse istisna fırlatır** ve bu istisna
///    `pumpAndSettle` sonrası **görünmez** kalabiliyor. Çözüm: `when(...)`
///    gövdesinin **içine** `debugPrint`/`captured` koyup iddiayı doğrudan
///    `updateCalls` sayacı üzerinden kurmak (bu dosyada `_SaveSpy`).
///
/// ⭐ Ayrıca `pumpWidget` **bir kez** kurulur; A4r10'un `_pumpDialog`'ı
/// `tester.runAsync` içinde `pumpWidget` çağırıyor ve ikinci bir
/// `pumpWidget` ile ezmek `EasyLocalization` durumunu bozuyordu.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/features/add/widgets/edit_meal_entry_dialog.dart';

class _MockDiary extends Mock implements DiaryRepository {}

const _kUser = User(
  id: 'u1',
  appMetadata: {},
  userMetadata: null,
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

/// Kaydedilen `updateMealEntry` çağrıları — `verify` yerine **doğrudan
/// sayaç** (yeşil test tuzağı: `verify` eşleşmezse istisna fırlatır ve o
/// istisna `pumpAndSettle` sonrası kaybolabilir).
class _SaveSpy {
  final calls = <Map<String, dynamic>>[];
  final ids = <String>[];
  final stamps = <String?>[];

  void record(String id, Map<String, dynamic> updates, String? expected) {
    ids.add(id);
    calls.add(updates);
    stamps.add(expected);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  /// Diyaloğu kurar ve `_save`'in async gövdesinin **gerçekten** bitmesini
  /// bekler (A2r12 tuzağı 1).
  Future<void> open(WidgetTester tester, MealEntry entry, _SaveSpy spy) async {
    final diary = _MockDiary();
    when(() => diary.updateMealEntry(any(), any(), any(),
            expectedUpdatedAt: any(named: 'expectedUpdatedAt')))
        .thenAnswer((inv) async {
      spy.record(
        inv.positionalArguments[1] as String,
        inv.positionalArguments[2] as Map<String, dynamic>,
        inv.namedArguments[#expectedUpdatedAt] as String?,
      );
      return entry;
    });

    // ⚠️ `pumpWidget` **bir kez** ve `tester.runAsync` içinde kurulur.
    // İlk ölçüm denemesinde önce boş bir `MaterialApp`, sonra `EasyLocalization`
    // pump edildi; `EasyLocalization` stateful bir widget ve **ikinci** kurulum
    // varlık ağacını `Bad state: No element` ile bozdu. A4r10'un
    // `_pumpDialog` deseni tek kurulumdur.
    //
    // ⭐ `Builder` + `context.localizationDelegates` şart: düz `MaterialApp`
    // `EasyLocalization`'ın çevirilerini **yüklemez** ve tüm anahtarlar
    // "not found" olur (ilk denemede oldu → metin iddiası sessizce 0
    // eşleşme verdi). A4r7b'in tuzağı: yeşil test, hiçbir şey ölçmüyor.
    await tester.runAsync(() async {
      await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('tr'), Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('tr'),
        startLocale: const Locale('tr'),
        child: Builder(
          builder: (context) => ProviderScope(
            overrides: [
              currentUserProvider.overrideWithValue(_kUser),
              diaryRepositoryProvider.overrideWithValue(diary),
            ],
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: Scaffold(body: EditMealEntryDialog(entry: entry)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    });
  }

  Future<void> tapSaveAndWait(WidgetTester tester) async {
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // ⭐ `pumpAndSettle` tek başına yetmez: `_save` async. Bu olmadan
    // `updateMealEntry` çağrısı testin sonunda da görünmez (yeşil test).
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

  String nameSeed(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first).controller!.text;

  // =========================================================================
  // 1) ÖLÇÜLEN ÖNCÜL DURUM — model
  // =========================================================================
  group('⭐ ölçüm: gıda silinince kayıt nasıl görünüyor?', () {
    test('`ON DELETE SET NULL` sonrası: food_id null, custom_name dolu', () {
      // A4r11'in yazdığı `canDelete` gıdası: `custom_name` korunur.
      const entry = MealEntry(
        id: 'e1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 150,
        calculatedKcal: 300,
        calculatedProtein: 30,
        calculatedCarbs: 5,
        calculatedFat: 20,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
        foodId: null, // FK SET NULL
        customName: 'Ev Yapımı Köfte',
      );
      expect(entry.foodId, isNull);
      expect(entry.displayName, 'Ev Yapımı Köfte',
          reason: 'P0 düzeltmesi (A4r11) çalışıyor: ad korunuyor');
    });

    test('topluluk gıdasından eklenen öğünde `custom_name` NULL', () {
      // A4r11'in raporundaki ölçüm: `add_from_food_dialog` yalnız
      // `isCustom || canDelete` için ad yazar → topluluk gıdasında NULL.
      const entry = MealEntry(
        id: 'e2',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 100,
        calculatedKcal: 90,
        calculatedProtein: 4,
        calculatedCarbs: 12,
        calculatedFat: 1,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
      );
      expect(entry.customName, isNull);
      expect(entry.displayName, 'Bilinmeyen',
          reason: 'dashboard\'da satır adsız — düzenleme ekranı bunu '
              'onarmalı');
    });
  });

  // =========================================================================
  // 2) ⭐ DÜZELTME: ad alanı artık boş açılmıyor
  // =========================================================================
  group('⭐ düzeltme: custom_name boşken ad alanı dolu açılır', () {
    testWidgets('food_id null + custom_name dolu → ad korunur, Kaydet açık',
        (tester) async {
      const entry = MealEntry(
        id: 'e1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 150,
        calculatedKcal: 300,
        calculatedProtein: 30,
        calculatedCarbs: 5,
        calculatedFat: 20,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
        customName: 'Ev Yapımı Köfte',
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);

      expect(nameSeed(tester), 'Ev Yapımı Köfte');
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('⭐ custom_name NULL → displayName seed edilir, Kaydet AÇIK',
        (tester) async {
      // ⚠️ Ölçülen kusur: bu satırda alan **boş** açılıyor ve Kaydet
      // **kapalı**ydı. Kullanıcı hangi yemeği düzenlediğini bilmiyordu.
      const entry = MealEntry(
        id: 'e2',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 100,
        calculatedKcal: 90,
        calculatedProtein: 4,
        calculatedCarbs: 12,
        calculatedFat: 1,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
        // custom_name: null, food_id: null → "Bilinmeyen"
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);

      // "Bilinmeyen" seed EDİLMEZ (veri uydurmak olurdu) ama kullanıcıya
      // **ne yapması** gerektiği söylenir.
      expect(nameSeed(tester), isEmpty);
      expect(find.textContaining('ad'), findsWidgets,
          reason: 'ipucu metni görünmeli (helperText)');
      expect(saveEnabled(tester), isFalse,
          reason: 'ad olmadan kaydetmek "Bilinmeyen" kaydını sürdürürdü');
    });

    testWidgets('⭐ "Bilinmeyen" etiketi ASLA yazılmaz (veri uydurulmaz)',
        (tester) async {
      const entry = MealEntry(
        id: 'e3',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 100,
        calculatedKcal: 90,
        calculatedProtein: 4,
        calculatedCarbs: 12,
        calculatedFat: 1,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);
      expect(nameSeed(tester), isNot(contains('Bilinmeyen')),
          reason: 'modelin placeholder etiketi kullanıcının girdisi olamaz');
    });
  });

  // =========================================================================
  // 3) ⭐ ETKİNLİK ÖLÇÜMÜ: Kaydet GERÇEKTEN yazıyor mu?
  // =========================================================================
  group('⭐ kaydetme akışı gerçekten yazıyor (etkin test)', () {
    testWidgets('ad dolu: tap → updateMealEntry ÇAĞRILIR (0 değil!)',
        (tester) async {
      const entry = MealEntry(
        id: 'e1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 150,
        calculatedKcal: 300,
        calculatedProtein: 30,
        calculatedCarbs: 5,
        calculatedFat: 20,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
        customName: 'Ev Yapımı Köfte',
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);

      await tapSaveAndWait(tester);

      // ⭐ Ham sayaç. `verify(...).called(1)` yazsaydı, `pumpAndSettle`
      // sonrası kaybolan bir istisna testi yine yeşil gösterebilirdi.
      expect(spy.ids, hasLength(1),
          reason: 'Kaydet’e basıldı ve `_save` **gerçekten** çalışmalı');
      expect(spy.ids.single, 'e1');
    });

    testWidgets('⭐ `source`/`food_id`/`photo_url`/`entry_date` KORUNUR',
        (tester) async {
      // `updateMealEntry` kısmi güncellemedir; göçü bozan şey
      // `food_id`/`source`un yanlışlıkla NULL\'a yazılmasıydı.
      const entry = MealEntry(
        id: 'e1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 150,
        calculatedKcal: 300,
        calculatedProtein: 30,
        calculatedCarbs: 5,
        calculatedFat: 20,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
        customName: 'Ev Yapımı Köfte',
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);
      await tapSaveAndWait(tester);

      final updates = spy.calls.single;
      expect(updates.containsKey('food_id'), isFalse,
          reason: 'gıda silinmişse `food_id` NULL kalmalı; yeniden yazılırsa '
              'FK\'li bir gıdaya geri bağlanırdı');
      expect(updates.containsKey('source'), isFalse);
      expect(updates.containsKey('photo_url'), isFalse);
      expect(updates.containsKey('entry_date'), isFalse);
      expect(updates.containsKey('deleted_at'), isFalse,
          reason: 'yumuşak silinmiş satır "yeniden doğar" olamaz');
      // Ad ve miktar **yazılır** — asıl düzenleme bu.
      expect(updates['custom_name'], 'Ev Yapımı Köfte');
      expect(updates['meal_type'], 'lunch');
    });

    testWidgets('ad boşken: tap → HİÇ yazılmaz (kapalı düğme)', (tester) async {
      const entry = MealEntry(
        id: 'e3',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 100,
        calculatedKcal: 90,
        calculatedProtein: 4,
        calculatedCarbs: 12,
        calculatedFat: 1,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);
      expect(saveEnabled(tester), isFalse);

      await tapSaveAndWait(tester);

      expect(spy.ids, isEmpty,
          reason: 'kapalı düğmeye basmak `custom_name: ""` yazmamalı — '
              'dashboard\'da satır yine "Bilinmeyen" olurdu');
    });

    testWidgets('⭐ kurtarma yolu: ad yazılınca kayıt GERÇEKTEN düzelir',
        (tester) async {
      // A2r12 ölçümü: "ad gir → Kaydet" yolu çalışıyordu; ölçüm bunu
      // `debugPrint` ile kanıtladı. Buradaki iddia: o yol **hâlâ** çalışıyor
      // ve `custom_name` gerçekten yazılıyor.
      const entry = MealEntry(
        id: 'e3',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 100,
        calculatedKcal: 90,
        calculatedProtein: 4,
        calculatedCarbs: 12,
        calculatedFat: 1,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);

      await tester.enterText(find.byType(TextField).first, 'Yoğurt');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);

      await tapSaveAndWait(tester);

      expect(spy.ids, hasLength(1));
      expect(spy.calls.single['custom_name'], 'Yoğurt');
      // Yazılan kayıt düzgün: `displayName` artık "Bilinmeyen" değil.
      final written = MealEntry.fromJson({
        'id': 'e3',
        'user_id': 'u1',
        'food_id': null,
        'custom_name': 'Yoğurt',
        'meal_type': 'lunch',
        'amount_g_ml': 100.0,
        'calculated_kcal': 90.0,
        'calculated_protein': 4.0,
        'calculated_carbs': 12.0,
        'calculated_fat': 1.0,
        'entry_date': '2026-09-28',
        'source': 'manual',
        'created_at': '2026-09-28T00:00:00Z',
      });
      expect(written.displayName, 'Yoğurt');
      expect(written.displayName, isNot('Bilinmeyen'));
    });

    testWidgets('miktar 0 → kayıt bozulmaz (yazma olmaz)', (tester) async {
      const entry = MealEntry(
        id: 'e1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 150,
        calculatedKcal: 300,
        calculatedProtein: 30,
        calculatedCarbs: 5,
        calculatedFat: 20,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
        customName: 'Ev Yapımı Köfte',
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);

      await tester.enterText(find.byType(TextField).at(1), '0');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isFalse,
          reason: '0 gamlık kayıt 100g normalizasyonunu bozar');

      await tapSaveAndWait(tester);
      expect(spy.ids, isEmpty);
    });

    testWidgets('iyimser kilit damgası ekrandaki kayıttan gelir',
        (tester) async {
      const entry = MealEntry(
        id: 'e1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 150,
        calculatedKcal: 300,
        calculatedProtein: 30,
        calculatedCarbs: 5,
        calculatedFat: 20,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T00:00:00Z',
        updatedAt: '2026-09-28T10:00:00Z',
        customName: 'Ev Yapımı Köfte',
      );
      final spy = _SaveSpy();
      await open(tester, entry, spy);
      await tapSaveAndWait(tester);

      expect(spy.stamps, hasLength(1));
      expect(spy.stamps.single, '2026-09-28T10:00:00Z',
          reason: 'kayıp güncelleme kilidi: iki cihazda aynı öğün açıksa '
              'ikinci kaydetme sessizce ezmemeli');
    });
  });
}
