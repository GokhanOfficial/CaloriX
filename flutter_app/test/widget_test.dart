import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calorix/shared/widgets/placeholder_page.dart';

void main() {
  setUpAll(() {
    // PlaceholderPage artık `.tr()` kullanıyor; çevirilerin gerçekten
    // yüklenmesi için easy_localization + SharedPreferences mock'u gerekir.
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  testWidgets('PlaceholderPage başlık ve ikonu gösterir', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('tr'), Locale('en')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('tr'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: const PlaceholderPage(
                title: 'DashboardPage',
                icon: Icons.dashboard,
              ),
            ),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();

    expect(find.text('DashboardPage'), findsNWidgets(2)); // appBar + body
    expect(find.byIcon(Icons.dashboard), findsOneWidget);
    // `common.comingSoon` artık 12 dilde mevcut (A6 commit d886ff6:
    // tr="Çok yakında", en="Coming soon") → çözümlenen metin beklenir.
    // easy_localization eksik anahtarda anahtarın kendisini döndürür;
    // yani bu assertion ham anahtarın ÇÖZÜLMEDİĞİNİ de yakalar.
    expect(find.text('Çok yakında'), findsOneWidget);
    expect(find.text('common.comingSoon'), findsNothing);
  });
}
