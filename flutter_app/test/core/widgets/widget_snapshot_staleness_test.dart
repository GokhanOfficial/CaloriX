import 'dart:convert';

import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/widgets/widget_settings.dart';
import 'package:calorix/core/widgets/widget_snapshot.dart';
import 'package:calorix/core/widgets/widget_strings.dart';
import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/data/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Widget veri bayatlama / pencere sınırı mantığı.
///
/// `widget_snapshot_test.dart` mutlak değerleri doğruluyor; burada zaman
/// penceresi sınırları (gece yarısı, ay sonu, yıl sonu), veri bayatlama
/// (`updatedAt`) ve ayar aynalarının snapshot'a yansıması kilitleniyor.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr');
    await initializeDateFormatting('en');
  });

  const strings = WidgetStrings(
    dailyTitle: 'Günlük',
    weeklyTitle: 'Haftalık',
    remaining: 'kalan',
    kcal: 'kcal',
    avg: 'ort.',
    onTarget: 'gün hedefte',
    quickAdd: 'Ekle',
    signedOut: 'Giriş yap',
    staleHint: 'Veri güncel değil',
    encMorning: 'sabah',
    encAfternoon: 'ogleden sonra',
    encEvening: 'aksam',
    nudgeTitle: 'nudge',
    nudgeBody: 'nudge govde',
  );

  MealEntry meal({String entryDate = '2026-09-25', double kcal = 1000}) =>
      MealEntry(
        id: 'm1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 200,
        calculatedKcal: kcal,
        calculatedProtein: 30,
        calculatedCarbs: 50,
        calculatedFat: 20,
        entryDate: entryDate,
        source: 'manual',
        createdAt: '${entryDate}T12:00:00Z',
      );

  List<Map<String, dynamic>> rows(Map<String, num> byDate) => [
        for (final e in byDate.entries)
          {'entry_date': e.key, 'calculated_kcal': e.value},
      ];

  group('weeklyCalorieValues — pencere sınırları', () {
    test('ay sonu geçişi: 31 Ocak → 1 Şubat penceresi doğru kurulur', () {
      // 2026-01-31 Cmt. Pencere 25 Ocak (Paz) → 31 Ocak (Cmt).
      final values = weeklyCalorieValues(
        mealRows: rows({
          '2026-01-25': 100,
          '2026-01-31': 700,
          '2026-01-24': 9999, // bir gün önce → pencere dışı
          '2026-02-01': 8888, // gelecek → yok sayılır
        }),
        today: DateTime(2026, 1, 31),
      );
      expect(values, [100, 0, 0, 0, 0, 0, 700]);
    });

    test('Şubat 2026 (28 gün) geçişi — leap yıl kuralı', () {
      final values = weeklyCalorieValues(
        mealRows: rows({'2026-02-28': 500, '2026-03-01': 600}),
        today: DateTime(2026, 2, 28),
      );
      // 22 Şubat → 28 Şubat; 1 Mart pencere dışı.
      expect(values, [0, 0, 0, 0, 0, 0, 500]);
    });

    test('yıl sonu geçişi: 31 Aralık → 1 Ocak', () {
      // today=31 Ara → pencere 25 Ara (indeks 0) … 31 Ara (indeks 6).
      // 27 Ara, 25 Ara'dan 2 gün sonra → indeks 2.
      final values = weeklyCalorieValues(
        mealRows: rows({'2025-12-27': 300, '2025-12-31': 900}),
        today: DateTime(2025, 12, 31),
      );
      expect(values, [0, 0, 300, 0, 0, 0, 900]);
    });

    test('bugünün zaman damgası gece yarısını geçse de aynı güne sayılır', () {
      // 25 Eylül 23:59 → formatEntryDate 25 Eylül; 26 Eylül 00:01 → 26 Eylül.
      final gece = weeklyCalorieValues(
        mealRows: rows({'2026-09-25': 400}),
        today: DateTime(2026, 9, 25, 23, 59, 59),
      );
      // today=26 Eylül → pencere 20 Eylül (0) … 26 Eylül (6).
      // 25 Eylül, 20 Eylül'den 5 gün sonra → indeks 5.
      final sabah = weeklyCalorieValues(
        mealRows: rows({'2026-09-25': 400}),
        today: DateTime(2026, 9, 26, 0, 0, 1),
      );
      expect(gece.last, 400);
      expect(sabah, [0, 0, 0, 0, 0, 400, 0]);
    });

    test('ondalık toplamlar yuvarlanır (yarı yukarı)', () {
      final values = weeklyCalorieValues(
        mealRows: rows({'2026-09-25': 1800.6}),
        today: DateTime(2026, 9, 25),
      );
      expect(values.last, 1801);
    });

    test('ondalık toplamlar yuvarlanır (yarı aşağı)', () {
      final values = weeklyCalorieValues(
        mealRows: rows({'2026-09-25': 1800.4}),
        today: DateTime(2026, 9, 25),
      );
      expect(values.last, 1800);
    });

    test('pencere tamamen boşsa yedi sıfır', () {
      final values = weeklyCalorieValues(
        mealRows: const [],
        today: DateTime(2026, 9, 25),
      );
      expect(values, List<int>.filled(7, 0));
    });
  });

  group('buildDailySnapshot — updatedAt veri bayatlama', () {
    test('updatedAt epoch ms — widget tarafı yaşı hesaplayabilir', () {
      final now = DateTime(2026, 9, 25, 14, 30, 15);
      final map = buildDailySnapshot(
        daily: DailyData.empty,
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.updatedAt], now.millisecondsSinceEpoch);
      // Tür int olmalı — native taraf Long bekliyor.
      expect(map[WidgetKeys.updatedAt], isA<int>());
    });

    test('her çağrı updatedAt\'i tazeler (bayatlık azalır)', () {
      final ilk = buildDailySnapshot(
        daily: DailyData.empty,
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: DateTime(2026, 9, 25, 10),
        localeCode: 'tr',
      );
      final sonra = buildDailySnapshot(
        daily: DailyData.empty,
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: DateTime(2026, 9, 25, 11),
        localeCode: 'tr',
      );
      expect(
        (sonra[WidgetKeys.updatedAt]! as int) -
            (ilk[WidgetKeys.updatedAt]! as int),
        3600000,
      );
    });

    test('tarih anahtarı yerel saate göre yyyy-MM-dd', () {
      final map = buildDailySnapshot(
        daily: DailyData.empty,
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: DateTime(2026, 1, 5, 8),
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.date], '2026-01-05');
    });
  });

  group('buildDailySnapshot — ayar aynası', () {
    test('dShow* anahtarları ayarları birebir yansıtır (native ayna)', () {
      final map = buildDailySnapshot(
        daily: DailyData.empty,
        profile: null,
        settings: const WidgetSettings(
          showMacros: false,
          showWater: false,
          showWeight: true,
        ),
        strings: strings,
        now: DateTime(2026, 9, 25, 14),
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.dShowMacros], isFalse);
      expect(map[WidgetKeys.dShowWater], isFalse);
      expect(map[WidgetKeys.dShowWeight], isTrue);
    });

    test('haftalık aynalar da ayarları yansıtır', () {
      final map = buildWeeklySnapshot(
        mealRows: const [],
        profile: null,
        settings: const WidgetSettings(
          weeklyShowAvg: false,
          weeklyShowDaysOnTarget: false,
        ),
        strings: strings,
        now: DateTime(2026, 9, 25, 14),
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.wShowAvg], isFalse);
      expect(map[WidgetKeys.wShowOnTarget], isFalse);
    });
  });

  group('buildWeeklySnapshot — hedef bandı ve ortalama', () {
    final now = DateTime(2026, 9, 25, 14);

    test('hedef 0 iken hiçbir gün "hedefte" sayılmaz (bölme koruması)', () {
      final map = buildWeeklySnapshot(
        mealRows: rows({'2026-09-25': 2000}),
        profile: const Profile(
          id: 'u1',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
          dailyCalorieTarget: 0,
        ),
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.wOnTarget], 0);
      // Ortalama yine de hesaplanır (mantıksal 0 değil, gerçek gün).
      expect(map[WidgetKeys.wAvg], 2000);
    });

    test('ortalamada bugün yarım gün de tam gün sayılır', () {
      final map = buildWeeklySnapshot(
        mealRows: rows({'2026-09-24': 1000, '2026-09-25': 3000}),
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      // (1000+3000)/2 = 2000 — gün sayısı kayıt olan günlerdir.
      expect(map[WidgetKeys.wAvg], 2000);
      // 1000 kcal hedefin (%50) altında, 3000 (%150) üstünde → bandın
      // dışında. Hedefte gün sayısı 0 olmalı; ortalama yine de 2000.
      expect(map[WidgetKeys.wOnTarget], 0);
    });

    test('varsayılan hedefin %90-110 bandındaki iki gün sayılır', () {
      final map = buildWeeklySnapshot(
        mealRows: rows({'2026-09-24': 2000, '2026-09-25': 2000}),
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      // 2000/2000 = %100 → bandın içinde.
      expect(map[WidgetKeys.wOnTarget], 2);
      expect(map[WidgetKeys.wAvg], 2000);
    });

    test('sıfır hedefte permille 0 (bölme koruması, daily)', () {
      final map = buildDailySnapshot(
        daily: DailyData(mealEntries: [meal(kcal: 2000)], waterEntries: const []),
        profile: const Profile(
          id: 'u1',
          createdAt: '2026-01-01T00:00:00Z',
          updatedAt: '2026-01-01T00:00:00Z',
          dailyCalorieTarget: 0,
        ),
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.dTarget], 0);
      expect(map[WidgetKeys.dPermille], 0);
      expect(map[WidgetKeys.dRemaining], 0);
    });

    test('haftalık JSON dizileri daima 7 elemanlı ve geçerli', () {
      final map = buildWeeklySnapshot(
        mealRows: rows({'2026-09-25': 100}),
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      final values = jsonDecode(map[WidgetKeys.wValues]! as String) as List;
      final labels = jsonDecode(map[WidgetKeys.wLabels]! as String) as List;
      expect(values, hasLength(7));
      expect(labels, hasLength(7));
      // Bugün her zaman son indeks.
      expect(map[WidgetKeys.wTodayIdx], 6);
      expect(values[6], 100);
    });

    test('labels boş string değil — her gün için etiket üretilir', () {
      final map = buildWeeklySnapshot(
        mealRows: const [],
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      final labels =
          (jsonDecode(map[WidgetKeys.wLabels]! as String) as List).cast<String>();
      expect(labels.every((l) => l.trim().isNotEmpty), isTrue);
    });
  });

  group('buildStateSnapshot — tüm anahtarlar mevcut', () {
    test('signedOut snapshot\'ı daily+weekly sözleşmesinin tamamını doldurur', () {
      final map = buildStateSnapshot(
        state: 'signedOut',
        strings: strings,
        now: DateTime(2026, 9, 25, 16),
        localeCode: 'tr',
      );
      // Dart tarafında üretilen tüm anahtarların tamamı bulunmalı; eksik
      // anahtar native tarafta eski kalıntı olarak ekranda kalır.
      for (final key in <String>[
        WidgetKeys.state,
        WidgetKeys.date,
        WidgetKeys.updatedAt,
        WidgetKeys.locale,
        WidgetKeys.dCalories,
        WidgetKeys.dTarget,
        WidgetKeys.dRemaining,
        WidgetKeys.dPermille,
        WidgetKeys.dProtein,
        WidgetKeys.dProteinT,
        WidgetKeys.dCarbs,
        WidgetKeys.dCarbsT,
        WidgetKeys.dFat,
        WidgetKeys.dFatT,
        WidgetKeys.dWater,
        WidgetKeys.dWaterT,
        WidgetKeys.dWeightText,
        WidgetKeys.dHasMeals,
        WidgetKeys.dEncText,
        WidgetKeys.dShowMacros,
        WidgetKeys.dShowWater,
        WidgetKeys.dShowWeight,
        WidgetKeys.wValues,
        WidgetKeys.wLabels,
        WidgetKeys.wTodayIdx,
        WidgetKeys.wTarget,
        WidgetKeys.wAvg,
        WidgetKeys.wOnTarget,
        WidgetKeys.wShowAvg,
        WidgetKeys.wShowOnTarget,
        WidgetKeys.sDailyTitle,
        WidgetKeys.sWeeklyTitle,
        WidgetKeys.sSignedOut,
        WidgetKeys.sStale,
        WidgetKeys.sRemaining,
        WidgetKeys.sKcal,
        WidgetKeys.sAvg,
        WidgetKeys.sOnTarget,
        WidgetKeys.sQuickAdd,
      ]) {
        expect(map.containsKey(key), isTrue, reason: 'eksik anahtar: $key');
      }
    });

    test('ready olmayan durumda teşvik metni boş string (null değil)', () {
      final map = buildStateSnapshot(
        state: 'noConfig',
        strings: strings,
        now: DateTime(2026, 9, 25, 19),
        localeCode: 'tr',
      );
      // Native taraf null'ı "anahtar yok" sanabilir; boş string güvenli.
      expect(map[WidgetKeys.dEncText], '');
      expect(map[WidgetKeys.dEncText], isA<String>());
    });

    test('bilinmeyen durum adı da geçerli bir snapshot üretir', () {
      final map = buildStateSnapshot(
        state: 'weirdState',
        strings: strings,
        now: DateTime(2026, 9, 25),
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.state], 'weirdState');
    });
  });

  group('shouldSendNudge — saat ve gün sınırları', () {
    const settings = WidgetSettings(nudgeEnabled: true, nudgeHour: 20, nudgeMinute: 0);

    test('gece yarısını geçince gün değişir → tekrar gönderilir', () {
      // 25 Eylül 23:50'de gönderildi, 26 Eylül 20:05 → yeni gün, tekrar.
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: false,
          now: DateTime(2026, 9, 26, 20, 5),
          lastNudgeDate: '2026-09-25',
        ),
        isTrue,
      );
    });

    test('aynı gün iki kez gönderilmez (lastNudgeDate == bugün)', () {
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 20, 0),
          lastNudgeDate: '2026-09-25',
        ),
        isFalse,
      );
    });

    test('gece yarısından hemen sonra planlanan saatten önce gönderilmez', () {
      // 26 Eylül 00:01 → 20:00\'e kadar bekle.
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: false,
          now: DateTime(2026, 9, 26, 0, 1),
          lastNudgeDate: '2026-09-25',
        ),
        isFalse,
      );
    });

    test('nudge saati 00:00 ise gece yarısında gönderilir', () {
      expect(
        shouldSendNudge(
          settings: const WidgetSettings(nudgeEnabled: true, nudgeHour: 0, nudgeMinute: 0),
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 0, 0),
          lastNudgeDate: '2026-09-24',
        ),
        isTrue,
      );
    });

    test('dakika eşiği tam saattedir (20:00:00 gönderir)', () {
      expect(
        shouldSendNudge(
          settings: const WidgetSettings(nudgeEnabled: true, nudgeHour: 20, nudgeMinute: 30),
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 20, 30),
          lastNudgeDate: null,
        ),
        isTrue,
      );
      expect(
        shouldSendNudge(
          settings: const WidgetSettings(nudgeEnabled: true, nudgeHour: 20, nudgeMinute: 30),
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 20, 29, 59),
          lastNudgeDate: null,
        ),
        isFalse,
      );
    });

    test('biçimsiz lastNudgeDate gönderimi engellemez (güvenli varsayılan)', () {
      // Beklenmedik veri (ör. bozuk prefs) kullanıcıyı kilitlememeli.
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 21),
          lastNudgeDate: 'bozuk-deger',
        ),
        isTrue,
      );
    });
  });

  group('encouragementText — saat eşikleri', () {
    test('tam 11:00 eşiği — sabah varyantı başlar', () {
      expect(
        encouragementText(
          s: strings,
          hasMeals: false,
          enabled: true,
          now: DateTime(2026, 9, 25, 11, 0),
        ),
        strings.encMorning,
      );
    });

    test('tam 12:00 eşiği — öğleden sonra varyantı', () {
      expect(
        encouragementText(
          s: strings,
          hasMeals: false,
          enabled: true,
          now: DateTime(2026, 9, 25, 12, 0),
        ),
        strings.encAfternoon,
      );
    });

    test('tam 18:00 eşiği — akşam varyantı', () {
      expect(
        encouragementText(
          s: strings,
          hasMeals: false,
          enabled: true,
          now: DateTime(2026, 9, 25, 18, 0),
        ),
        strings.encEvening,
      );
    });

    test('10:59 son saniye hâlâ null', () {
      expect(
        encouragementText(
          s: strings,
          hasMeals: false,
          enabled: true,
          now: DateTime(2026, 9, 25, 10, 59, 59),
        ),
        isNull,
      );
    });
  });

  group('varsayılan hedeflerin snapshot\'a yansıması', () {
    test('profil yokken tüm hedefler AppConstants varsayılanı', () {
      final map = buildDailySnapshot(
        daily: DailyData.empty,
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: DateTime(2026, 9, 25, 14),
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.dTarget], AppConstants.defaultCalories);
      expect(map[WidgetKeys.dProteinT], AppConstants.defaultProtein);
      expect(map[WidgetKeys.dCarbsT], AppConstants.defaultCarbs);
      expect(map[WidgetKeys.dFatT], AppConstants.defaultFat);
      expect(map[WidgetKeys.dWaterT], AppConstants.defaultWater);
    });
  });
}
