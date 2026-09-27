import 'dart:convert';

import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/core/widgets/widget_settings.dart';
import 'package:calorix/core/widgets/widget_snapshot.dart';
import 'package:calorix/core/widgets/widget_strings.dart';
import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/models/water_entry.dart';
import 'package:calorix/data/models/weight_entry.dart';
import 'package:calorix/data/models/profile.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Widget snapshot çekirdeğinin saf hesapları — Supabase/kanal bağımlılığı
/// yok, tüm girdiler elle kurulur.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr');
    await initializeDateFormatting('en');
  });

  // Belirli test grubunda yeniden kullanılan sabitler.
  const strings = WidgetStrings(
    dailyTitle: 'Günlük Özet',
    weeklyTitle: 'Haftalık Grafik',
    remaining: 'kalan',
    kcal: 'kcal',
    avg: 'ort.',
    onTarget: 'gün hedefte',
    quickAdd: 'Ekle',
    signedOut: 'Özetini görmek için giriş yap',
    staleHint: 'Veri güncel değil — uygulamayı aç',
    encMorning: 'Güne güzel başla, kahvaltını ekle',
    encAfternoon: 'Öğlenyi değerlendir',
    encEvening: 'Akşam özetini kaçırma',
    nudgeTitle: 'Bugün hiçbir şey eklemedin',
    nudgeBody: 'Kalorini görmek için öğün ekle',
  );

  MealEntry meal({
    String entryDate = '2026-09-25',
    double kcal = 500,
    double protein = 30,
    double carbs = 50,
    double fat = 20,
  }) => MealEntry(
    id: 'm1',
    userId: 'u1',
    mealType: 'lunch',
    amountGMl: 200,
    calculatedKcal: kcal,
    calculatedProtein: protein,
    calculatedCarbs: carbs,
    calculatedFat: fat,
    entryDate: entryDate,
    source: 'manual',
    createdAt: '2026-09-25T12:00:00Z',
  );

  group('buildDailySnapshot', () {
    test('değerler profilden, toplamlar yuvarlanmış', () {
      final profile = Profile(
        id: 'u1',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
        dailyCalorieTarget: 2200,
        proteinTargetG: 140,
        carbsTargetG: 220,
        fatTargetG: 70,
        dailyWaterTargetMl: 3000,
      );
      final daily = DailyData(
        mealEntries: [
          meal(kcal: 550.6, protein: 35.4, carbs: 60.2, fat: 18.7),
          meal(kcal: 249.7, protein: 14.6, carbs: 39.8, fat: 11.3),
        ],
        waterEntries: const [
          WaterEntry(
            id: 'w1',
            userId: 'u1',
            amountMl: 750,
            entryDate: '2026-09-25',
          ),
          WaterEntry(
            id: 'w2',
            userId: 'u1',
            amountMl: 250.4,
            entryDate: '2026-09-25',
          ),
        ],
        latestWeight: WeightEntry(
          id: 'wt1',
          userId: 'u1',
          weightKg: 82.34,
          entryDate: '2026-09-20',
        ),
      );

      final now = DateTime(2026, 9, 25, 14, 0);
      final map = buildDailySnapshot(
        daily: daily,
        profile: profile,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );

      expect(map[WidgetKeys.state], 'ready');
      expect(map[WidgetKeys.date], '2026-09-25');
      expect(map[WidgetKeys.updatedAt], now.millisecondsSinceEpoch);
      expect(map[WidgetKeys.locale], 'tr');
      expect(map[WidgetKeys.dCalories], 800); // 550.6 + 249.7 = 800.3 → 800
      expect(map[WidgetKeys.dTarget], 2200);
      expect(map[WidgetKeys.dRemaining], 1400);
      expect(map[WidgetKeys.dPermille], 364); // 800.3/2200*1000 = 363.8 → 364
      expect(map[WidgetKeys.dProtein], 50); // 35.4+14.6 = 50
      expect(map[WidgetKeys.dProteinT], 140);
      expect(map[WidgetKeys.dCarbs], 100);
      expect(map[WidgetKeys.dCarbsT], 220);
      expect(map[WidgetKeys.dFat], 30);
      expect(map[WidgetKeys.dFatT], 70);
      expect(map[WidgetKeys.dWater], 1000); // 750 + 250.4 = 1000.4 → 1000
      expect(map[WidgetKeys.dWaterT], 3000);
      expect(map[WidgetKeys.dWeightText], '82.3 kg');
      expect(map[WidgetKeys.dHasMeals], isTrue);
      expect(map[WidgetKeys.dShowMacros], isTrue);
      expect(map[WidgetKeys.dShowWater], isTrue);
      expect(map[WidgetKeys.dShowWeight], isFalse);
      // Metin paketi de gömülü.
      expect(map[WidgetKeys.sDailyTitle], 'Günlük Özet');
      expect(map[WidgetKeys.sQuickAdd], 'Ekle');
    });

    test('profil yoksa AppConstants varsayılan hedefleri kullanılır', () {
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
      expect(map[WidgetKeys.dHasMeals], isFalse);
      expect(map[WidgetKeys.dWeightText], '');
    });

    test('permille hedef aşımında 1000\'e kırpılır, remaining 0\'da kalır', () {
      final daily = DailyData(
        mealEntries: [meal(kcal: 3000)],
        waterEntries: const [],
      );
      final map = buildDailySnapshot(
        daily: daily,
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: DateTime(2026, 9, 25, 14),
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.dRemaining], 0);
      expect(map[WidgetKeys.dPermille], 1000);
    });

    group('encouragementText', () {
      test('11 öncesi → null (gün henüz yeni)', () {
        expect(
          encouragementText(
            s: strings,
            hasMeals: false,
            enabled: true,
            now: DateTime(2026, 9, 25, 10, 59),
          ),
          isNull,
        );
      });

      test('11:00-11:59 → sabah varyantı', () {
        expect(
          encouragementText(
            s: strings,
            hasMeals: false,
            enabled: true,
            now: DateTime(2026, 9, 25, 11),
          ),
          strings.encMorning,
        );
      });

      test('14:00 → öğleden sonra varyantı', () {
        expect(
          encouragementText(
            s: strings,
            hasMeals: false,
            enabled: true,
            now: DateTime(2026, 9, 25, 14),
          ),
          strings.encAfternoon,
        );
      });

      test('19:00 → akşam varyantı', () {
        expect(
          encouragementText(
            s: strings,
            hasMeals: false,
            enabled: true,
            now: DateTime(2026, 9, 25, 19),
          ),
          strings.encEvening,
        );
      });

      test('kapalıysa null', () {
        expect(
          encouragementText(
            s: strings,
            hasMeals: false,
            enabled: false,
            now: DateTime(2026, 9, 25, 19),
          ),
          isNull,
        );
      });

      test('gün doluysa null', () {
        expect(
          encouragementText(
            s: strings,
            hasMeals: true,
            enabled: true,
            now: DateTime(2026, 9, 25, 19),
          ),
          isNull,
        );
      });
    });
  });

  group('buildWeeklySnapshot', () {
    // 2026-09-25 Cuma.
    final now = DateTime(2026, 9, 25, 15);

    /// Pencere: 19 (Cmt) → 25 (Cum), eski→bugün.
    List<Map<String, dynamic>> rowsFor(Map<String, num> byDate) => [
      for (final e in byDate.entries)
        {'entry_date': e.key, 'calculated_kcal': e.value},
    ];

    test('kayan pencere sınırları — pencere dışı günler sayılmaz', () {
      final values = weeklyCalorieValues(
        mealRows: rowsFor({
          '2026-09-18': 9000, // pencere dışı (bir hafta önce) → yok sayılır
          '2026-09-19': 1800,
          '2026-09-25': 2100,
        }),
        today: DateTime(2026, 9, 25),
      );
      expect(values, [
        1800, 0, 0, 0, 0, 0, 2100, // 7 öğe, eski→bugün
      ]);
    });

    test('etiketler kısa gün adları, 7 öğe (tr)', () {
      final labels = weeklyLabels(
        today: DateTime(2026, 9, 25),
        localeCode: 'tr',
      );
      expect(labels.length, 7);
      expect(labels.first, 'Cmt'); // 19 Eylül 2026 Cumartesi
      expect(labels.last, 'Cum'); // 25 Eylül 2026 Cuma
    });

    test('ortalama yalnızca kayıtlı günlere bölünür', () {
      final map = buildWeeklySnapshot(
        mealRows: rowsFor({
          '2026-09-19': 1800,
          '2026-09-21': 2000,
          '2026-09-25': 2200,
        }),
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      // (1800+2000+2200)/3 = 2000
      expect(map[WidgetKeys.wAvg], 2000);
      expect(map[WidgetKeys.wTodayIdx], 6);
      expect(map[WidgetKeys.wTarget], AppConstants.defaultCalories);
      // 1800 (%90 sınırı dahil), 2000, 2200 (%110 = 2200 dahil) → 3 gün hedefte.
      expect(map[WidgetKeys.wOnTarget], 3);
      // JSON dizileri geçerli ve 7 öğe.
      expect((jsonDecode(map[WidgetKeys.wValues] as String) as List).length, 7);
      expect((jsonDecode(map[WidgetKeys.wLabels] as String) as List).length, 7);
      expect(map[WidgetKeys.wShowAvg], isTrue);
      expect(map[WidgetKeys.wShowOnTarget], isTrue);
      expect(map[WidgetKeys.sWeeklyTitle], 'Haftalık Grafik');
    });

    test('hiç kayıt yoksa avg=0, onTarget=0', () {
      final map = buildWeeklySnapshot(
        mealRows: const [],
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.wAvg], 0);
      expect(map[WidgetKeys.wOnTarget], 0);
      expect(
        jsonDecode(map[WidgetKeys.wValues] as String),
        List<int>.filled(7, 0),
      );
    });

    test('%90-110 bandı dışı günler hedefte sayılmaz', () {
      final map = buildWeeklySnapshot(
        mealRows: rowsFor({
          '2026-09-19': 1790, // %89.5 → bandın altı
          '2026-09-20': 1800, // %90 → dahil
          '2026-09-21': 2200, // %110 → dahil
          '2026-09-22': 2201, // %110.05 → bandın üstü
        }),
        profile: null,
        settings: const WidgetSettings(),
        strings: strings,
        now: now,
        localeCode: 'tr',
      );
      expect(map[WidgetKeys.wOnTarget], 2);
    });

    test('aynı güne birden çok kayıt toplanır', () {
      final values = weeklyCalorieValues(
        mealRows: rowsFor({'2026-09-25': 800}) + rowsFor({'2026-09-25': 400}),
        today: DateTime(2026, 9, 25),
      );
      expect(values.last, 1200);
    });
  });

  group('buildStateSnapshot', () {
    test(
      'signedOut — tüm anahtarlara güvenli varsayılanlar + metin paketi',
      () {
        final now = DateTime(2026, 9, 25, 16);
        final map = buildStateSnapshot(
          state: 'signedOut',
          strings: strings,
          now: now,
          localeCode: 'tr',
        );
        expect(map[WidgetKeys.state], 'signedOut');
        expect(map[WidgetKeys.date], '2026-09-25');
        expect(map[WidgetKeys.updatedAt], now.millisecondsSinceEpoch);
        expect(map[WidgetKeys.dCalories], 0);
        expect(map[WidgetKeys.dTarget], 0);
        expect(map[WidgetKeys.dPermille], 0);
        expect(map[WidgetKeys.dHasMeals], isFalse);
        expect(map[WidgetKeys.dWeightText], '');
        expect(
          jsonDecode(map[WidgetKeys.wValues] as String),
          List<int>.filled(7, 0),
        );
        expect(map[WidgetKeys.wTodayIdx], 6);
        expect(map[WidgetKeys.sSignedOut], strings.signedOut);
        expect(map[WidgetKeys.sStale], strings.staleHint);
        // str.* paketindeki tüm anahtarlar mevcut.
        expect(
          map.keys,
          containsAll([
            WidgetKeys.sDailyTitle,
            WidgetKeys.sWeeklyTitle,
            WidgetKeys.sRemaining,
            WidgetKeys.sKcal,
            WidgetKeys.sAvg,
            WidgetKeys.sOnTarget,
            WidgetKeys.sQuickAdd,
          ]),
        );
      },
    );

    test('noConfig durumu da aynı güvenli varsayılanlarla gelir', () {
      final map = buildStateSnapshot(
        state: 'noConfig',
        strings: strings,
        now: DateTime(2026, 9, 25, 16),
        localeCode: 'en',
      );
      expect(map[WidgetKeys.state], 'noConfig');
      expect(map[WidgetKeys.locale], 'en');
    });
  });

  group('shouldSendNudge', () {
    final settings = const WidgetSettings(nudgeEnabled: true); // 20:00

    test('planlanan saatten önce gönderilmez', () {
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 19, 59),
          lastNudgeDate: null,
        ),
        isFalse,
      );
    });

    test('planlanan saatte gönderilir', () {
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 20, 0),
          lastNudgeDate: null,
        ),
        isTrue,
      );
    });

    test('bugün zaten gönderildiyse tekrar gönderilmez', () {
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 21, 0),
          lastNudgeDate: '2026-09-25',
        ),
        isFalse,
      );
    });

    test('dün gönderildiyse bugün gönderilir', () {
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 21, 0),
          lastNudgeDate: '2026-09-24',
        ),
        isTrue,
      );
    });

    test('kapalıysa gönderilmez', () {
      expect(
        shouldSendNudge(
          settings: const WidgetSettings(nudgeEnabled: false),
          hasMealsToday: false,
          now: DateTime(2026, 9, 25, 22, 0),
          lastNudgeDate: null,
        ),
        isFalse,
      );
    });

    test('bugün öğün varsa gönderilmez', () {
      expect(
        shouldSendNudge(
          settings: settings,
          hasMealsToday: true,
          now: DateTime(2026, 9, 25, 22, 0),
          lastNudgeDate: null,
        ),
        isFalse,
      );
    });
  });
}
