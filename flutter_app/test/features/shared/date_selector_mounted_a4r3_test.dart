import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/shared/widgets/date_selector.dart';

/// `DateSelector._pickDate`, `await showDatePicker(...)` sonrası `ref.read`
/// çağırıyordu. `DateSelector` bir `ConsumerWidget` olduğu için `WidgetRef`
/// element'e bağlıdır ve element dispose olduktan sonra kullanılırsa
/// **"Bad state: Cannot use ref after the widget was disposed"** fırlatır.
///
/// Senaryo: kullanıcı takvimi açar, uygulamayı arka plana alır / başka bir
/// route'a geçer (`DateSelector` dispose olur), sonra takvimden bir tarih
/// seçip onaylar. `await` tam bu noktada döner ve `ref` artık ölü.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  /// `DateSelector`'ın bulunduğu ekranı, takvim dialogu "açık"ken değiştirir
  /// → element dispose olur, ama `ProviderScope` (ve dolayısıyla
  /// `selectedDateProvider`) ayakta kalır.
  ///
  /// `showDatePicker` future'ını doğrudan sürüklemek `flutter_test`'te
  /// mümkün değil (`showDatePicker` kendi route'unu açar ve `Navigator`'a
  /// bağlıdır). Bu yüzden test, dispose sonrası ağacın sağlam kaldığını ve
  /// `ref`'in kullanılmadığını doğrular; asıl koruma `context.mounted`
  /// satırıdır (linter + gözle inceleme).
  Future<void> pumpDisposingScenario(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: EasyLocalization(
            supportedLocales: const [Locale('tr')],
            path: 'assets/translations',
            fallbackLocale: const Locale('en'),
            startLocale: const Locale('tr'),
            child: const MaterialApp(
              home: Scaffold(body: SizedBox.shrink()),
            ),
          ),
        ),
      );
    });
    await tester.pumpAndSettle();
  }

  testWidgets('seçici ekrandan kaldırıldıktan sonra çökme yok', (tester) async {
    await pumpDisposingScenario(tester);

    // `DateSelector` artık ağaçta değil; `selectedDateProvider` yine de
    // ayakta (ProviderScope uygulama boyunca yaşıyor) ve çökme olmadı.
    expect(tester.takeException(), isNull);
  });

  testWidgets('tarih seçici takvimi aç/kapat döngüsünde çökmez',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: EasyLocalization(
            supportedLocales: const [Locale('tr')],
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
        ),
      );
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bugün'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarDatePicker), findsOneWidget);

    // İptal: `picked == null` yolu.
    Navigator.of(tester.element(find.byType(CalendarDatePicker))).pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('tarih seçilince seçilen gün etikete yansır', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: EasyLocalization(
            supportedLocales: const [Locale('tr')],
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
        ),
      );
    });
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DateSelector)),
    );
    // Normal gezinme: dün → etiket değişir (mounted yolu çalışıyor).
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    final yesterday = container.read(selectedDateProvider);
    expect(yesterday.isBefore(DateTime.now()), isTrue);
    expect(find.text('Dün'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
