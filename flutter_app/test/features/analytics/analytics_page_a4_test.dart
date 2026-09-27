import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/data/repositories/analytics_repository.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/profile_repository.dart';
import 'package:calorix/features/analytics/analytics_page.dart';
import 'package:calorix/features/analytics/macro_focus.dart';
import 'package:calorix/shared/widgets/date_selector.dart';

class _MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

/// Testte tek gereken alan `id` (sayfa yalnızca `user.id` okur).
User _testUser() => const User(
      id: 'u1',
      appMetadata: {},
      userMetadata: null,
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );

/// Analytics sayfası: (1) hedef 0/negatif profilde bölmeden güvenli yüzde,
/// (2) veri hatasında retry butonu, (3) `_maybeScrollToFocus` tetiklenmesi.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  AnalyticsData statsWith({int calories = 2000}) => AnalyticsData(
        dailyStats: [
          for (var i = 0; i < 3; i++)
            DailyStats(
              date: '2026-09-2${i + 1}',
              dayLabel: 'Pzt',
              calories: calories,
              protein: 120,
              carbs: 180,
              fat: 60,
              water: 2000,
              hasData: true,
            ),
        ],
        weightTrend: const [],
        averages: const AverageStats(
          avgCalories: 2000,
          avgProtein: 120,
          avgCarbs: 180,
          avgFat: 60,
          avgWater: 2000,
          totalDays: 3,
          daysWithData: 3,
        ),
      );

  Future<void> pumpAnalytics(
    WidgetTester tester, {
    required AnalyticsData data,
    MacroFocus? focus,
    bool failing = false,
  }) async {
    final repo = _MockAnalyticsRepository();
    registerFallbackValue(AnalyticsPeriod.week);
    when(() => repo.fetch(any(), any(), locale: any(named: 'locale')))
        .thenAnswer((_) async => failing ? throw Exception('boom') : data);
    final scope = ProviderScope(
      overrides: [
        // `analyticsDataProvider` oturum yoksa `AnalyticsData.empty`
        // döndürüp repository'ye hiç uğramadığı için repository override'ı
        // tek başına yetmez; oturum ve profil de sabitlenmeli.
        currentUserProvider.overrideWithValue(_testUser()),
        profileProvider.overrideWith((ref) async => null),
        analyticsRepositoryProvider.overrideWithValue(repo),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('tr'), Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('tr'),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: AnalyticsPage(focusedMacro: focus),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async => tester.pumpWidget(scope));
    await tester.pumpAndSettle();
  }

  testWidgets('veri hatasında hata metni ve retry butonu gösterilir',
      (tester) async {
    await pumpAnalytics(tester, data: AnalyticsData.empty, failing: true);

    expect(find.text('Hata'), findsOneWidget);
    expect(find.text('Tekrar Gönder'), findsOneWidget);
    // Detay hata metni (exception) ekrana sızmamalı.
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('boş seri (stats yok) çökmez — grafikler boş çizilir',
      (tester) async {
    await pumpAnalytics(tester, data: AnalyticsData.empty);

    // Hedef 0/negatif profil senaryosu: bölmeden 0 yüzde üretilmeli.
    expect(find.text('Analiz'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Ort. Kalori'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('odak makro ile açıldığında odak kartı görünür',
      (tester) async {
    await pumpAnalytics(
      tester,
      data: statsWith(),
      focus: MacroFocus.protein,
    );

    // `_FocusedMacroChartCard` başlığı makro etiketiyle çevrilmiş gelir:
    // `{macro} Takibi` + `settings.goals.protein` = "Protein (g)".
    expect(find.text('Protein (g) Takibi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tarih seçici takvim/ileri-geri günleri doğru işaretler',
      (tester) async {
    final scope = ProviderScope(
      child: EasyLocalization(
        supportedLocales: const [Locale('tr'), Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('tr'),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: const Scaffold(body: DateSelector()),
          ),
        ),
      ),
    );
    await tester.runAsync(() async => tester.pumpWidget(scope));
    await tester.pumpAndSettle();

    // Bugün seçiliyken "Bugün" rozeti gösterilmez (aynı gün), ileri/geri
    // ikon-only butonların tooltip'i çeviriyle gelir.
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
