import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/models/water_entry.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/features/dashboard/dashboard_page.dart';

class _MockDiaryRepository extends Mock implements DiaryRepository {}

/// Dashboard sayfası render testleri.
///
/// Supabase'e dokunmadan: [dailyDataProvider] fixture ile override edilir,
/// profil provider'ı boş (varsayılan hedefler) kalır. easy_localization
/// çevirileri gerçek tr.json üzerinden çözülür — anahtar kayması hem
/// UI'daki `.tr()` çağrılarını hem JSON'u aynı anda doğrular.
Future<void> _pumpDashboard(
  WidgetTester tester, {
  required DailyData daily,
}) async {
  // easy_localization çevirileri gerçek (fake async dışı) I/O ile yüklenir;
  // runAsync olmadan ilk pump'ta boş sözlük kalır ve anahtarlar çözülmez.
  // Görünür alan büyütülür: dashboard uzun bir ListView'dır ve lazy build
  // sayfa altındaki kartları (kilo/öğün) test yüzeyinde oluşturmaz.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyDataProvider.overrideWith((ref) async => daily),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('tr'), Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('tr'),
          // Uygulama (app.dart) ile aynı kalıp: delegate'ler EasyLocalization
          // bağlamından alınır; yoksa delegate.load() hiç çağrılmaz ve
          // .tr() ham anahtar döndürür.
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const DashboardPage(),
            ),
          ),
        ),
      ),
    );
  });
  await tester.pumpAndSettle();
}

void main() {
  final mockRepo = _MockDiaryRepository();

  setUpAll(() {
    // Test ortamında plugin kanalı yoktur; shared_preferences mock'u
    // EasyLocalization'un locale deposunu (ensureInitialized) besler.
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    reset(mockRepo);
    // Sayfa yenileme (RefreshIndicator vb.) fetchDaily'yi çağırabilir;
    // testler yalnızca ilk frame'i besleyen provider override'ına güvenir.
    when(() => mockRepo.fetchDaily(any(), any()))
        .thenAnswer((_) async => DailyData.empty);
  });

  MealEntry entry(
    String id,
    MealType type, {
    double kcal = 0,
    double protein = 0,
    double carbs = 0,
    double fat = 0,
  }) =>
      MealEntry(
        id: id,
        userId: 'u1',
        foodId: null,
        customName: 'Yumurta ($id)',
        mealType: type.name,
        amountGMl: 100,
        calculatedKcal: kcal,
        calculatedProtein: protein,
        calculatedCarbs: carbs,
        calculatedFat: fat,
        entryDate: '2026-08-25',
        source: 'manual',
        createdAt: '2026-08-25T08:00:00Z',
      );

  testWidgets('boş gün: varsayılan hedeflerle kalan kalori ve su gösterilir',
      (tester) async {
    await _pumpDashboard(tester, daily: DailyData.empty);

    // Kalori halkası: tüketilen 0 / hedef 2000 → "2000 kalan kcal"
    // (sayı ve etiket ayrı Text widget'larıdır).
    expect(find.text('2000'), findsOneWidget);
    expect(find.text('kalan kcal'), findsOneWidget);
    expect(find.text('0 / 2000 kcal'), findsOneWidget);

    // Su kartı: 0 / 2500 ml + hızlı ekle butonları.
    expect(find.text('0 / 2500 ml'), findsOneWidget);
    expect(find.text('+250'), findsOneWidget);
    expect(find.text('+500'), findsOneWidget);
    expect(find.text('2500 ml kaldı'), findsOneWidget);

    // Öğün kartları her zaman görünür (4 öğün), ama girdi yok.
    expect(find.text('Kahvaltı'), findsOneWidget);
    expect(find.text('Atıştırmalık'), findsOneWidget);

    // Kilo kartı: kayıt yokken title "Kilo Kaydet" ve subtitle
    // `dashboard.recordWeight` çevirisidir (weight_card.dart:157).
    expect(find.text('Kilo Kaydet'), findsOneWidget);
    expect(find.text('Kilonuzu kaydedin'), findsOneWidget);
    // "Kayıt gir" gibi bir metin hiçbir yerde yok — öğün toplamı 0 kcal
    // gövde metni olarak 4 öğün kartında da görünür.
    expect(find.text('0 kcal'), findsNWidgets(4));
  });

  testWidgets('dolu gün: toplamlar, öğün girdisi ve su birikimi gösterilir',
      (tester) async {
    final data = DailyData(
      mealEntries: [
        entry('e1', MealType.breakfast, kcal: 300, protein: 20),
        entry('e2', MealType.lunch, kcal: 450, carbs: 40),
      ],
      waterEntries: [
        WaterEntry(
          id: 'w1',
          userId: 'u1',
          amountMl: 250,
          entryDate: '2026-08-25',
          entryTime: '08:05:00',
          createdAt: '2026-08-25T08:05:00Z',
        ),
      ],
    );

    await _pumpDashboard(tester, daily: data);

    // Halka: 750/2000 → 1250 kalan; makro kartı: protein 20g / 150g.
    expect(find.text('1250'), findsOneWidget);
    expect(find.text('750 / 2000 kcal'), findsOneWidget);
    expect(find.text('20g'), findsOneWidget);
    expect(find.text('/ 150g'), findsOneWidget);

    // Girdi satırları: isim, miktar ve kalori değerleri.
    expect(find.text('Yumurta (e1)'), findsOneWidget);
    expect(find.text('Yumurta (e2)'), findsOneWidget);

    // "300 kcal" iki yerde geçer: kahvaltı kartının öğün toplamı
    // (meal_section.dart:121) ve girdi satırının trailing değeri
    // (meal_section.dart:157). Kart toplamı ile satır değerinin ayrı
    // ayrı doğrulanması gerekiyor — `findsNWidgets(2)` tek başına
    // hangisinin nerede olduğunu kanıtlamaz, bu yüzden kapsam daraltılır.
    expect(
      find.descendant(
        of: find.byType(Dismissible),
        matching: find.text('300 kcal'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dismissible),
        matching: find.text('450 kcal'),
      ),
      findsOneWidget,
    );
    // Kart toplamları (öğün alt başlığı) — her iki öğünde tek kayıt var.
    expect(find.text('300 kcal'), findsNWidgets(2));
    expect(find.text('450 kcal'), findsNWidgets(2));
    // Akşam ve atıştırma boş → 0 kcal.
    expect(find.text('0 kcal'), findsNWidgets(2));

    // Su: 250 / 2500 ml.
    expect(find.text('250 / 2500 ml'), findsOneWidget);
  });
}
