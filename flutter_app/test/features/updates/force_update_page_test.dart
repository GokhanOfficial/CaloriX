import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:calorix/core/updates/update_manifest.dart';
import 'package:calorix/features/updates/force_update_page.dart';

/// `ForceUpdatePage` — uzak manifestten gelen `apkUrl` doğrudan
/// `url_launcher`'a veriliyordu. `javascript:` / `intent:` / `file:` /
/// `content:` şemaları cihazdaki başka uygulamaya açılabiliyordu (açık
/// yönlendirme yüzeyi). Ekran artık `UpdateManifest.isSafeApkUrl` kapısından
/// geçmek zorunda.
void main() {
  const launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

  late List<MethodCall> launches;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.ensureInitialized();
  });

  setUp(() {
    launches = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, (call) async {
      switch (call.method) {
        case 'canLaunch':
          return true;
        case 'launch':
          launches.add(call);
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcherChannel, null);
  });

  Future<void> pumpPage(WidgetTester tester, String apkUrl) async {
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
            home: ForceUpdatePage(
              manifest: UpdateManifest.fromJson({
                'versionName': '9.9.9',
                'versionCode': 99,
                'minSupportedVersionCode': 99,
                'apkUrl': apkUrl,
              }),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async => tester.pumpWidget(scope));
    await tester.pumpAndSettle();
  }

  /// "Güncelle" butonuna bas, SnackBar metnini ve launch çağrılarını topla.
  Future<String> tapUpdate(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.download));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final bars = tester.widgetList<SnackBar>(find.byType(SnackBar));
    if (bars.isEmpty) return '';
    final content = bars.last.content;
    return content is Text ? (content.data ?? '') : '';
  }

  group('güvenli apkUrl', () {
    testWidgets('https GitHub APK adresi kabul edilir ve launch edilir',
        (tester) async {
      const url = 'https://github.com/GokhanOfficial/CaloriX/releases/'
          'download/android-v9.9.9%2B99/calorix.apk';
      await pumpPage(tester, url);

      await tapUpdate(tester);
      expect(launches, isNotEmpty, reason: 'launchUrl çağrılmalı');
      expect('${launches.single.arguments['url']}', contains('.apk'));
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('güvensiz apkUrl — launch edilmez', () {
    const cases = <String, String>{
      'javascript şeması': 'javascript:alert(document.cookie)',
      'intent şeması':
          'intent://scan/#Intent;scheme=zxing;package=com.zxing;end',
      'file şeması': 'file:///data/data/com.calorix/shared_prefs/x.xml',
      'data şeması': 'data:text/html,<script>alert(1)</script>',
      'content şeması': 'content://com.calorix.provider/evil',
      'http (düz metin)': 'http://example.com/calorix.apk',
      'market şeması': 'market://details?id=com.evil.app',
      'boş adres': '',
      'format hatalı': '::::',
      'apk uzantısı yok': 'https://evil.example.com/redirect?to=js',
      'userInfo gömülü': 'https://user:pass@evil.example.com/a.apk',
    };

    cases.forEach((label, url) {
      testWidgets('$label reddedilir, url_launcher çağrılmaz', (tester) async {
        await pumpPage(tester, url);

        final message = await tapUpdate(tester);
        expect(launches, isEmpty,
            reason: '$label için dış uygulama açılmamalı');
        expect(message, isNotEmpty, reason: 'kullanıcı bilgilendirilmeli');
        expect(tester.takeException(), isNull);
      });
    });
  });

  testWidgets('süzgeç saf süzgeçle aynı kararı verir', (tester) async {
    // Ekranın kapısı ile `UpdateManifest.isSafeApkUrl` sonucu birebir aynı
    // olmalı; sapma olursa açık yönlendirme yüzeyi yeniden açılır.
    const safe = 'https://example.com/calorix.apk';
    const unsafe = 'javascript:alert(1)';
    expect(UpdateManifest.isSafeApkUrl(safe), isTrue);
    expect(UpdateManifest.isSafeApkUrl(unsafe), isFalse);

    await pumpPage(tester, safe);
    await tapUpdate(tester);
    expect(launches, isNotEmpty);

    await pumpPage(tester, unsafe);
    await tapUpdate(tester);
    expect(launches, isNotEmpty); // yalnızca güvenli olan çağrıldı
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
