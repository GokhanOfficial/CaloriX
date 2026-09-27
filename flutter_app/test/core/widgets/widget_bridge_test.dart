import 'dart:convert';

import 'package:calorix/core/widgets/widget_bridge.dart';
import 'package:calorix/core/widgets/widget_settings.dart';
import 'package:calorix/core/widgets/widget_strings.dart';
import 'package:calorix/core/widgets/widget_snapshot.dart';
import 'package:calorix/data/models/profile.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dart→native widget veri köprüsü testleri.
///
/// `home_widget` platform kanalı widget testlerinde `MissingPluginException`
/// verdiği için [HomeWidgetSave] üzerinden sahte uygulama enjekte edilir;
/// böylece hangi anahtarların hangi tipte yazıldığı doğrulanabilir.
void main() {
  late Map<String, Object?> written;
  late List<String> refreshed;

  setUp(() {
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
    HomeWidgetSave.update = (name) async {
      refreshed.add(name);
      return true;
    };
  });

  tearDown(HomeWidgetSave.reset);

  group('publish', () {
    test('tüm anahtarları yazar ve iki provider\'ı da tazeler', () async {
      await WidgetBridge.publish({
        WidgetKeys.state: 'ready',
        WidgetKeys.dCalories: 1234,
        WidgetKeys.dHasMeals: true,
        WidgetKeys.dWeightText: '78.4 kg',
      });

      expect(written[WidgetKeys.state], 'ready');
      expect(written[WidgetKeys.dCalories], 1234.0); // int → double
      expect(written[WidgetKeys.dHasMeals], true);
      expect(written[WidgetKeys.dWeightText], '78.4 kg');
      expect(refreshed, containsAll(['DailyWidgetProvider', 'WeeklyWidgetProvider']));
    });

    test('null değerler atlanır (native tarafın null beklemesin)', () async {
      await WidgetBridge.publish({
        WidgetKeys.dWeightText: null,
        WidgetKeys.dCalories: 10,
      });
      expect(written.containsKey(WidgetKeys.dWeightText), isFalse);
      expect(written[WidgetKeys.dCalories], 10.0);
    });

    test('NaN/Infinity 0\'a indirilir (JSON yazılamaz)', () async {
      await WidgetBridge.publish({
        WidgetKeys.dPermille: double.nan,
        WidgetKeys.dTarget: double.infinity,
        WidgetKeys.dRemaining: -double.nan,
      });
      expect(written[WidgetKeys.dPermille], 0.0);
      expect(written[WidgetKeys.dTarget], 0.0);
      expect(written[WidgetKeys.dRemaining], 0.0);
      // Yazılan hiçbir değer NaN değil.
      expect(written.values.whereType<double>().any((v) => v.isNaN), isFalse);
    });

    test('liste/dirde değerleri JSON metnine çevrilir', () async {
      await WidgetBridge.publish({
        WidgetKeys.wValues: [1, 2, 3],
        'obj': {'a': 1},
      });
      expect(jsonDecode(written[WidgetKeys.wValues]! as String), [1, 2, 3]);
      expect(jsonDecode(written['obj']! as String), {'a': 1});
    });

    test('platform hatası yutulur, çağıran taraf çökmez', () async {
      HomeWidgetSave.saveString = (k, v) async => throw Exception('channel down');
      // publish kendi hatasını yakalar → test buraya düşmemeli.
      await expectLater(
        WidgetBridge.publish({WidgetKeys.state: 'ready'}),
        completes,
      );
    });
  });

  group('publishDaily', () {
    test('profil hedefleri snapshot\'a yansır', () async {
      final daily = DailyData(
        mealEntries: [],
        waterEntries: [],
        latestWeight: null,
      );
      final profile = Profile(
        id: 'u1',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
        dailyCalorieTarget: 2400,
        proteinTargetG: 150,
        carbsTargetG: 250,
        fatTargetG: 70,
        dailyWaterTargetMl: 3000,
      );
      await WidgetBridge.publishDaily(
        daily: daily,
        profile: profile,
        settings: const WidgetSettings(),
        strings: _strings(),
        now: DateTime(2026, 9, 27, 14, 30),
        localeCode: 'tr',
      );

      expect(written[WidgetKeys.dTarget], 2400.0);
      expect(written[WidgetKeys.dProteinT], 150.0);
      expect(written[WidgetKeys.dWaterT], 3000.0);
      expect(written[WidgetKeys.state], 'ready');
      // Gün boş → teşvik metni (saat 14'te öğleden sonra varyantı).
      expect(written[WidgetKeys.dEncText], 'enc-afternoon');
    });

    test('profil yoksa AppConstants varsayılanları kullanılır', () async {
      await WidgetBridge.publishDaily(
        daily: DailyData.empty,
        profile: null,
        settings: const WidgetSettings(),
        strings: _strings(),
        now: DateTime(2026, 9, 27, 9),
        localeCode: 'tr',
      );
      // Varsayılan hedef 2000 (AppConstants).
      expect(written[WidgetKeys.dTarget], greaterThan(0));
      expect(written[WidgetKeys.dPermille], 0.0);
    });
  });

  group('publishState', () {
    test('signedOut durumu tüm sayısal alanları sıfırlar', () async {
      await WidgetBridge.publishState(
        state: 'signedOut',
        strings: _strings(),
        localeCode: 'tr',
      );
      expect(written[WidgetKeys.state], 'signedOut');
      expect(written[WidgetKeys.dCalories], 0.0);
      expect(written[WidgetKeys.dTarget], 0.0);
      expect(written[WidgetKeys.dRemaining], 0.0);
      expect(written[WidgetKeys.dPermille], 0.0);
      // Haftalık alanlar da sıfırlanmalı (native taraf null beklemiyor).
      expect(written[WidgetKeys.wValues], '[0,0,0,0,0,0,0]');
    });
  });

  group('isWidgetKey', () {
    test('veri kanalı anahtarlarını kabul eder', () {
      expect(isWidgetKey(WidgetKeys.state), isTrue);
      expect(isWidgetKey(WidgetKeys.dCalories), isTrue);
      expect(isWidgetKey(WidgetKeys.wValues), isTrue);
      expect(isWidgetKey(WidgetKeys.sKcal), isTrue);
    });

    test('Dart ayar anahtarlarını süzmez (isim çakışması önlenir)', () {
      expect(isWidgetKey('widget_show_macros'), isFalse);
      expect(isWidgetKey('reminder_enabled'), isFalse);
      expect(isWidgetKey('theme_mode'), isFalse);
    });
  });
}

WidgetStrings _strings() => const WidgetStrings(
  dailyTitle: 'Günlük Özet',
  weeklyTitle: 'Haftalık Grafik',
  remaining: 'kalan',
  kcal: 'kcal',
  avg: 'ort.',
  onTarget: 'gün hedefte',
  quickAdd: 'Ekle',
  signedOut: 'Giriş yap',
  staleHint: 'Veri güncel değil',
  encMorning: 'enc-morning',
  encAfternoon: 'enc-afternoon',
  encEvening: 'enc-evening',
  nudgeTitle: 'nudge-title',
  nudgeBody: 'nudge-body',
);
