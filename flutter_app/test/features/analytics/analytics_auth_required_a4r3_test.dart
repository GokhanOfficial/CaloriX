import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calorix/core/router/app_router.dart';
import 'package:calorix/data/repositories/analytics_repository.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/profile_repository.dart';
import 'package:calorix/features/analytics/analytics_page.dart';

class _MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

/// `analyticsDataProvider` oturum yoksa repository'ye **gitmeden**
/// `AnalyticsAuthRequired` fırlatır (A2'nin bilinçli kararı: "veri yok" ile
/// "giriş yapmamış" ayrımı). UI bu tipi yakalayıp "Giriş yap" çağrısı
/// göstermeli; eskiden genel `_ErrorView` ("Hata" / "Tekrar Gönder")
/// gösteriliyordu ve retry hiçbir işe yaramıyordu.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  Future<void> pumpAuthRequired(WidgetTester tester) async {
    final repo = _MockAnalyticsRepository();
    // Repository'ye **hiç** ulaşılmamalı.
    registerFallbackValue(AnalyticsPeriod.week);
    when(() => repo.fetch(any(), any(), locale: any(named: 'locale')))
        .thenAnswer((_) async => throw StateError('repository çağrılmamalı'));

    final router = GoRouter(
      initialLocation: AppRoutes.analytics,
      routes: [
        GoRoute(
          path: AppRoutes.analytics,
          builder: (_, _) => const AnalyticsPage(),
        ),
        GoRoute(
          path: AppRoutes.auth,
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('GIRIS EKRANI')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(null),
            profileProvider.overrideWith((ref) async => null),
            analyticsRepositoryProvider.overrideWithValue(repo),
            appRouterProvider.overrideWithValue(router),
          ],
          child: EasyLocalization(
            supportedLocales: const [Locale('tr'), Locale('en')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            startLocale: const Locale('tr'),
            child: Builder(
              builder: (context) => MaterialApp.router(
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                locale: context.locale,
                routerConfig: router,
              ),
            ),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();
  }

  testWidgets('oturum yokken "giriş yap" çağrısı gösterilir', (tester) async {
    await pumpAuthRequired(tester);

    // Genel hata ekranı gösterilmemeli.
    expect(find.text('Hata'), findsNothing);
    expect(find.text('Tekrar Gönder'), findsNothing);

    // "Giriş yap" butonu var.
    expect(find.widgetWithText(FilledButton, 'Giriş Yap'), findsOneWidget);
  });

  testWidgets('oturum yokken boş/grafik durumu gösterilmez', (tester) async {
    await pumpAuthRequired(tester);

    // Boş seri başlığı ("Analiz" app bar dışında) görünmemeli.
    expect(find.text('Ort. Kalori'), findsNothing);
    expect(find.text('Kalori Takibi'), findsNothing);
    expect(find.text('Ortalama Makro Değerleri'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('çeviri anahtarı eksikse ham anahtar ekrana basılmaz',
      (tester) async {
    await pumpAuthRequired(tester);

    // `analytics.signInRequired` 12 dil dosyasında henüz yok; kullanıcı
    // "analytics.signInRequired" ham metnini görmemeli.
    expect(find.textContaining('analytics.signInRequired'), findsNothing);
    expect(
      find.text('Analitik verilerini görmek için giriş yap'),
      findsOneWidget,
    );
  });

  testWidgets('"Giriş yap" butonu oturum ekranına yönlendirir',
      (tester) async {
    await pumpAuthRequired(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Giriş Yap'));
    await tester.pumpAndSettle();

    expect(find.text('GIRIS EKRANI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
