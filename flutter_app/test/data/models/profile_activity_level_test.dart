import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/activity_level_map.dart';
import 'package:calorix/data/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Profile.activityLevel` tür güvenliği sözleşmesi.
///
/// Alan `String?` iken iki ayrı okuma noktası `activityLevelFromDb(...)`
/// çağırıyordu; DB CHECK kısıtı modelde **hiçbir şekilde** ifade edilmiyordu,
/// bu yüzden `ActivityLevel.veryActive.name` (`'veryActive'`) yazılabilir bir
/// değerdi. Yazılırsa `profiles` UPDATE'i CHECK ihlaliyle **başarısız** olur
/// (onboarding'de kullanıcı "Çok Aktif" seçiyor, hedefleri kaydedilemiyor).
///
/// Bu testler:
///  1. modelin tip güvenliğini (derleme düzeyi) belgeler,
///  2. `toJson` çıktısının **her zaman** CHECK kısıtında olduğunu kanıtlar
///     (asıl kırılma senaryosu),
///  3. bozuk DB değerinin çökmediğini ve **ham değerin korunduğunu** gösterir
///     (teşhis/yedek için `rawActivityLevel`),
///  4. `null` (onboarding tamamlanmamış) ile tanımsız değeri ayırır.
void main() {
  Map<String, dynamic> dbRow({Object? activityLevel}) => <String, dynamic>{
        'id': 'u1',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'activity_level': activityLevel,
      };

  group('Profile.fromJson — DB → enum', () {
    test('CHECK kısıtındaki beş değer doğru enum\'a çevrilir', () {
      final expected = <String, ActivityLevel>{
        'sedentary': ActivityLevel.sedentary,
        'light': ActivityLevel.light,
        'moderate': ActivityLevel.moderate,
        'active': ActivityLevel.active,
        'very_active': ActivityLevel.veryActive,
      };
      expect(expected.keys.toSet(), ActivityLevelMap.dbValueSet,
          reason: 'test tablosu DB CHECK kısıtından ayrışmış');
      for (final e in expected.entries) {
        expect(Profile.fromJson(dbRow(activityLevel: e.key)).activityLevel,
            e.value,
            reason: '${e.key} yanlış enum\'a çevrildi');
      }
    });

    test('null korunur (onboarding tamamlanmamış profil)', () {
      // `fromDb(null)` fallback döndürürdü; bu **yanlış** olurdu: henüz
      // aktivite seçmemiş bir kullanıcı "orta" görünürdü ve `isOnboardingComplete`
      // kontrolü yerine TDEE hesabı yapılırdı.
      final p = Profile.fromJson(dbRow(activityLevel: null));
      expect(p.activityLevel, isNull);
      expect(p.rawActivityLevel, isNull);
    });

    test('tanımsız değer fallback\'e düşer, ÇÖKMEZ, ham değer korunur', () {
      for (final bogus in <Object>[
        'veryActive', // eski istemcinin bıraktığı hatalı yazım
        'VERY_ACTIVE',
        'Hareketsiz', // çeviri metni
        '',
        '   ',
        42,
        true,
      ]) {
        final p = Profile.fromJson(dbRow(activityLevel: bogus));
        expect(p.activityLevel, ActivityLevelMap.fallback,
            reason: '$bogus fallback\'e düşmeli');
        expect(p.rawActivityLevel, bogus.toString(),
            reason: 'ham değer teşhis/yedek için korunmalı');
      }
    });

    test('`very_active` fallback\'e DÜŞMEZ (TDEE sapması regresyonu)', () {
      // Asıl hata: `asNameMap()['very_active']` null döndürüp 1.55 çarpanını
      // seçiyordu. 30y/erkek/175cm/80kg → doğru 3382 kcal, hatalı 2759 kcal.
      final p = Profile.fromJson(dbRow(activityLevel: 'very_active'));
      expect(p.activityLevel, ActivityLevel.veryActive);
      expect(p.activityLevel!.multiplier, 1.9);
    });
  });

  group('Profile.toJson — enum → DB (CHECK kısıtı garantisi)', () {
    test('her enum değeri CHECK kısıtında bir dizeye yazılır', () {
      for (final e in ActivityLevel.values) {
        final json = Profile.fromJson(dbRow()).copyWith(activityLevel: e).toJson();
        expect(json['activity_level'], ActivityLevelMap.toDb(e));
        expect(ActivityLevelMap.dbValueSet.contains(json['activity_level']),
            isTrue,
            reason: '$e → ${json['activity_level']} CHECK dışı');
      }
    });

    test('`.name` sızmaz: veryActive → very_active', () {
      final json = Profile.fromJson(dbRow()).copyWith(
        activityLevel: ActivityLevel.veryActive,
      ).toJson();
      expect(json['activity_level'], 'very_active');
      expect(json['activity_level'], isNot('veryActive'));
      expect(
        json['activity_level'],
        isNot(ActivityLevel.veryActive.name),
        reason: '`.name` gönderilirse CHECK ihlali → profil UPDATE başarısız',
      );
    });

    test('null → null (onboarding tamamlanmamış)', () {
      expect(
        Profile.fromJson(dbRow()).toJson()['activity_level'],
        isNull,
      );
    });

    test('tanımsız DB değeri → toJson kanonik değeri yazar', () {
      // Yedek başka bir istemciye (web) aktarılabilir olmalı: ham bozuk değer
      // JSON'a sızmaz, CHECK'te olan değere çevrilir.
      final p = Profile.fromJson(dbRow(activityLevel: 'veryActive'));
      expect(p.rawActivityLevel, 'veryActive');
      expect(p.toJson()['activity_level'], 'moderate');
    });

    test('round-trip: fromJson → toJson → fromJson sabit nokta', () {
      for (final e in ActivityLevel.values) {
        final p = Profile.fromJson(dbRow(activityLevel: ActivityLevelMap.toDb(e)));
        final again = Profile.fromJson(p.toJson());
        expect(again.activityLevel, e, reason: '$e round-trip kaybı');
        expect(again.toJson()['activity_level'], ActivityLevelMap.toDb(e));
      }
    });

    test('tam profil round-trip\'i: alan kaybı yok', () {
      final row = <String, dynamic>{
        'id': 'u1',
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-02T00:00:00Z',
        'display_name': 'Ayşe',
        'email': 'a@b.c',
        'avatar_url': 'https://x/y.png',
        'birth_date': '1996-04-12',
        'gender': 'female',
        'height_cm': 165.0,
        'current_weight_kg': 62.5,
        'target_weight_kg': 58.0,
        'activity_level': 'very_active',
        'goal': 'lose',
        'bmr': 1400.5,
        'tdee': 2660.0,
        'daily_calorie_target': 2160.0,
        'protein_target_g': 150.0,
        'carbs_target_g': 200.0,
        'fat_target_g': 67.0,
        'daily_water_target_ml': 2500.0,
        'weigh_in_frequency_days': 3,
        'push_notifications_enabled': true,
        'email_notifications_enabled': false,
        'onboarding_completed': true,
        'auto_recalculate_macros': true,
        'timezone': 'Europe/Istanbul',
      };
      final first = Profile.fromJson(row);
      final second = Profile.fromJson(first.toJson());

      expect(second.id, first.id);
      expect(second.displayName, first.displayName);
      expect(second.email, first.email);
      expect(second.avatarUrl, first.avatarUrl);
      expect(second.birthDate, first.birthDate);
      expect(second.gender, first.gender);
      expect(second.heightCm, first.heightCm);
      expect(second.currentWeightKg, first.currentWeightKg);
      expect(second.targetWeightKg, first.targetWeightKg);
      expect(second.activityLevel, ActivityLevel.veryActive);
      expect(second.goal, first.goal);
      expect(second.bmr, first.bmr);
      expect(second.tdee, first.tdee);
      expect(second.dailyCalorieTarget, first.dailyCalorieTarget);
      expect(second.proteinTargetG, first.proteinTargetG);
      expect(second.carbsTargetG, first.carbsTargetG);
      expect(second.fatTargetG, first.fatTargetG);
      expect(second.dailyWaterTargetMl, first.dailyWaterTargetMl);
      expect(second.weighInFrequencyDays, first.weighInFrequencyDays);
      expect(second.pushNotificationsEnabled, first.pushNotificationsEnabled);
      expect(second.emailNotificationsEnabled, first.emailNotificationsEnabled);
      expect(second.onboardingCompleted, first.onboardingCompleted);
      expect(second.autoRecalculateMacros, first.autoRecalculateMacros);
      expect(second.timezone, first.timezone);
      expect(second.isOnboardingComplete, isTrue);
    });
  });

  group('copyWith — yazma tarafı türle korunur', () {
    test('activityLevel güncellenir, ham değer korunur', () {
      final p = Profile.fromJson(dbRow(activityLevel: 'light'))
          .copyWith(activityLevel: ActivityLevel.veryActive);
      expect(p.activityLevel, ActivityLevel.veryActive);
      expect(p.rawActivityLevel, 'light',
          reason: 'ham değer teşhis için korunur; mantık enum\'a bakar');
      expect(p.toJson()['activity_level'], 'very_active');
    });

    test('activityLevel verilmezse mevcut değer korunur', () {
      final p = Profile.fromJson(dbRow(activityLevel: 'active'));
      expect(p.copyWith(displayName: 'X').activityLevel,
          ActivityLevel.active);
    });

    test('null profil → copyWith her şeyi null bırakır (derleme zamanı)', () {
      final p = Profile.fromJson(dbRow());
      expect(p.copyWith().activityLevel, isNull);
      expect(p.toJson()['activity_level'], isNull);
    });
  });

  group('i18n etiketi hâlâ üretilebilir', () {
    test('activityLevel.labelKey CHECK ile ilgisiz ama enum\'a bağlı', () {
      // Model enum'a çevrildiğinde `settings.goals.activity.*` etiketleri
      // bozulmamalı: `ActivityLevelMap.toDb` her değer için bir dize üretir.
      for (final e in ActivityLevel.values) {
        expect(ActivityLevelMap.toDb(e), isNotEmpty);
        expect(e.labelKey, startsWith('settings.goals.activity.'));
      }
    });
  });
}
