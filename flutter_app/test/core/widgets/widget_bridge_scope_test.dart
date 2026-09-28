import 'dart:async';

import 'package:calorix/core/widgets/widget_bridge.dart';
import 'package:calorix/core/widgets/widget_settings.dart';
import 'package:calorix/core/widgets/widget_snapshot.dart';
import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/data/repositories/profile_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `WidgetBridgeScope`in **gerçekten** veri akışına bağlandığını kanıtlayan
/// testler (widget testi, sahte `HomeWidgetSave` ile).
///
/// Tur 2 incelemesinde sorulan kritik soru: "`ref.listen<AsyncValue<DailyData>>`
/// ilk yayını tetikliyor mu, yoksa widget hiç güncelleniyor mu?"
/// Cevap: Riverpod `ref.listen`, `listen` çağrıldığı anda provider **ilk kez
/// okunduğunda** da (fireImmediately) callback'i çağırır. Bu test bunu
/// `override` edilmiş bir `FutureProvider` ile uçtan uca doğrular — yani
/// "asenkron ilk değer geldiğinde widget güncelleniyor mu?" sorusunun
/// cevabı burada sabitlenir.
void main() {
  late Map<String, Object?> written;
  late List<String> refreshed;

  setUp(() {
    // `WidgetSettingsNotifier._load`/`update` `SharedPreferences.getInstance()`
    // çağırıyor. Bu dosyada platform kanalı **mock'lanmıyor**: gerçek
    // platform eklentisine giden istek, test binding'i kapatmadan önce
    // çözülmemiş bir future bırakıyor ve flutter_test "Cannot close sink
    // while adding stream" ile tüm dosyayı düşürüyordu. Boş bir mock
    // yeterli: testler ayar **değerlerini** (`WidgetSettings`) doğrudan
    // veriyor, kalıcılık burada ölçülmüyor.
    SharedPreferences.setMockInitialValues(<String, Object>{});

    written = <String, Object?>{};
    refreshed = <String>[];
    HomeWidgetSave.saveBool = (k, v) async {
      written[k] = v;
      return true;
    };
    HomeWidgetSave.saveDouble = (k, v) async {
      written[k] = v;
      return true;
    };
    HomeWidgetSave.saveString = (k, v) async {
      written[k] = v;
      return true;
    };
    HomeWidgetSave.readString = (k) async => written[k] as String?;
    HomeWidgetSave.update = (name) async {
      refreshed.add(name);
      return true;
    };
  });

  tearDown(HomeWidgetSave.reset);

  /// Köprüyü tek frame'de kurup pump eder.
  ///
  /// `dailyDataProvider` ve `currentUserProvider` override edilir: gerçek
  /// ikisi de `supabaseClientProvider`'a zincirlidir ve widget testinde
  /// platform kanalı yoktur. Böylece test deterministik olur ve yalnızca
  /// köprünün **kendi** davranışı ölçülür.
  Future<void> pumpBridge(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) => null),
          ...overrides,
        ],
        child: MaterialApp(
          home: WidgetBridgeScope(
            child: Builder(
              builder: (context) => const Scaffold(body: Text('child')),
            ),
          ),
        ),
      ),
    );
  }

  group('günlük veri akışı', () {
    testWidgets('asenkron ilk değer geldiğinde widget YAYINLANIR', (tester) async {
      // `dailyDataProvider` gerçek bir FutureProvider'dır; testte
      // override edilmiş `FutureProvider.delayed` ile "önce loading,
      // sonra data" akışı taklit edilir.
      final completer = Completer<DailyData>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dailyDataProvider.overrideWith((ref) => completer.future),
            profileProvider.overrideWith((ref) => null),
          ],
          child: MaterialApp(
            home: WidgetBridgeScope(
              child: Builder(
                builder: (context) => const Scaffold(body: Text('child')),
              ),
            ),
          ),
        ),
      );

      // İlk frame: **günlük veri** henüz yok. Oturum durumu (`signedOut`
      // varsayılanı) yayınlanabilir; önemli olan günlük hedef/kalori
      // anahtarlarının yazılmamış olması. Nötr durum yayını bilinçlidir:
      // oturum okunamadığında şifreli ekranda widget'ın "veri yok"
      // göstermesi eski kalorilerin sızmasından iyidir.
      await tester.pump();
      expect(
        written[WidgetKeys.dTarget],
        anyOf(isNull, 0),
        reason: 'veri gelmeden günlük hedef gerçek değerle yayınlanmamalı '
            '(nötr durum snapshot\'ı 0 yazar, bu kabul edilebilir)',
      );

      // Veri geldi → köprü `ref.listen` callback'ini tetikler.
      completer.complete(DailyData.empty);
      await tester.pump();
      await tester.pump();

      expect(written[WidgetKeys.state], 'ready');
      expect(written.containsKey(WidgetKeys.dTarget), isTrue);
      expect(refreshed, contains('DailyWidgetProvider'));
    });

    testWidgets('provider HENÜZ okunmamışken de ilk yayın yapılır',
        (tester) async {
      // `ref.listen`, provider'ın **ilk okunduğu** anda da callback'i çağırır
      // (fireImmediately). Burada `currentUserProvider` null ve
      // `dailyDataProvider` senkron `DailyData.empty` döndüğü için ilk
      // yayın **build'in ilk frame'inde** gerçekleşmelidir.
      await pumpBridge(
        tester,
        overrides: [
          currentUserProvider.overrideWith((ref) => null),
          dailyDataProvider.overrideWith((ref) => DailyData.empty),
        ],
      );
      await tester.pump();
      await tester.pump();

      expect(written, isNotEmpty,
          reason: 'ref.listen ilk değeri kendiliğinden yayınlamalı');
      expect(refreshed, contains('DailyWidgetProvider'));
    });

    testWidgets('oturum yokken durum nötr (signedOut) yayınlanır',
        (tester) async {
      await pumpBridge(
        tester,
        overrides: [
          currentUserProvider.overrideWith((ref) => null),
          dailyDataProvider.overrideWith((ref) => DailyData.empty),
        ],
      );
      await tester.pump();
      await tester.pump();

      // `currentUserProvider` null → signedOut. Günlük veri de boş
      // olduğundan nötr değerler yazılır (eski kaloriler kalmaz).
      expect(written[WidgetKeys.state], 'signedOut');
      expect(written[WidgetKeys.dCalories], 0.0);
    });

    testWidgets('çıkışta eski kaloriler nötr duruma alınır', (tester) async {
      // Gerçek risk: `publishState` hiç çağrılmıyordu, `DailyDataProvider`
      // çıkışta `DailyData.empty` döndüğü için eski snapshot widget'ta
      // kalıyordu. Köprü oturum dinleyicisiyle bunu nötrlüyor.
      await pumpBridge(
        tester,
        overrides: [
          currentUserProvider.overrideWith((ref) => null),
          dailyDataProvider.overrideWith((ref) => DailyData.empty),
        ],
      );
      await tester.pump();
      await tester.pump();

      expect(written[WidgetKeys.state], 'signedOut');
      expect(written[WidgetKeys.dTarget], 0.0);
      expect(written[WidgetKeys.wValues], '[0,0,0,0,0,0,0]');
    });
  });

  group('ayarlar — görünürlük anahtarları korunur', () {
    testWidgets('görünürlük değişimi veri anahtarlarını SİLMEZ',
        (tester) async {
      // Ayar değişikliği tetiklensin: gövde önce `showMacros: true`, sonra
      // `WidgetSettingsNotifier.update` ile `false` yazıyor.
      await pumpBridge(
        tester,
        overrides: [
          currentUserProvider.overrideWith((ref) => null),
          dailyDataProvider.overrideWith((ref) => DailyData.empty),
        ],
      );
      await tester.pump();
      await tester.pump();

      // "Hazır" durumdaki bir günlük snapshot'ı **köprü kurulduktan sonra**
      // yaz: aksi hâlde köprünün nötr durum yayını (oturum okunamadığında
      // `signedOut` + tüm hedefler 0) bu değerleri ezer ve test, ayar
      // değişikliğinin koruduğu veriyi ölçemez.
      await WidgetBridge.publish({
        WidgetKeys.state: 'ready',
        WidgetKeys.dCalories: 1500.0,
        WidgetKeys.dTarget: 2000.0,
      });

      final container = ProviderScope.containerOf(
        tester.element(find.byType(WidgetBridgeScope)),
      );
      await container
          .read(widgetSettingsProvider.notifier)
          .update(const WidgetSettings(showMacros: false));
      await tester.pump();
      await tester.pump();

      // Makro bayrağı yazıldı ama **veri anahtarları korundu**.
      expect(written[WidgetKeys.dShowMacros], false);
      expect(written[WidgetKeys.dCalories], 1500.0);
      expect(written[WidgetKeys.dTarget], 2000.0);
    });
  });

  group('oturum çıkışı — eski veri sızmaz', () {
    test('refreshVisibility çıkış durumunda veri anahtarlarını bozmaz', () async {
      written[WidgetKeys.state] = 'signedOut';
      written[WidgetKeys.dCalories] = 999.0;
      await refreshVisibility(
        settings: const WidgetSettings(showMacros: false),
        localeCode: 'tr',
      );
      // Görünürlük bayrağı yazıldı, veri olduğu gibi kaldı.
      expect(written[WidgetKeys.dShowMacros], false);
      expect(written[WidgetKeys.dCalories], 999.0);
    });

    test('state null ise hiçbir şey yazılmaz (ilk açılış)', () async {
      await refreshVisibility(
        settings: const WidgetSettings(),
        localeCode: 'tr',
      );
      expect(written, isEmpty);
      expect(refreshed, isEmpty);
    });
  });
}
