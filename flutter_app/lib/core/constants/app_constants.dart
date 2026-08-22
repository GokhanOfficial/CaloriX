import 'package:flutter/foundation.dart';

/// CaloriX sabitleri — web `src/lib/constants.ts` karşılığı.
abstract final class AppConstants {
  static const String appVersion = '1.2.0';

  /// GitHub Releases — en son Android sürümünün manifesti (APK + min sürüm
  /// bilgisi). `tool/release_android.sh` her release'de günceller.
  static const String updateManifestUrl =
      'https://github.com/GokhanOfficial/CaloriX/releases/latest/download/latest.json';

  /// Varsayılan hedefler (hesaplama yapılamazsa).
  static const int defaultCalories = 2000;
  static const int defaultProtein = 150;
  static const int defaultCarbs = 200;
  static const int defaultFat = 65;
  static const int defaultWater = 2500;

  /// Su hızlı ekleme miktarları (ml).
  static const List<int> waterQuickAdd = [250, 500];
}

/// Aktivite seviyeleri — çarpanları web ile aynı.
enum ActivityLevel {
  sedentary(1.2),
  light(1.375),
  moderate(1.55),
  active(1.725),
  veryActive(1.9);

  const ActivityLevel(this.multiplier);

  /// TDEE hesaplamada kullanılan çarpan.
  final double multiplier;

  /// Çeviri anahtarı (settings.goals.activity.*).
  String get labelKey => switch (this) {
        ActivityLevel.sedentary => 'settings.goals.activity.sedentary',
        ActivityLevel.light => 'settings.goals.activity.light',
        ActivityLevel.moderate => 'settings.goals.activity.moderate',
        ActivityLevel.active => 'settings.goals.activity.active',
        ActivityLevel.veryActive => 'settings.goals.activity.very_active',
      };
}

/// Kilo hedefi — kalori modifikatörleri web ile aynı.
enum Goal {
  lose(-500),
  maintain(0),
  gain(500);

  const Goal(this.calorieModifier);

  /// Günlük kalori hedefine eklenecek değer.
  final int calorieModifier;

  /// Çeviri anahtarı (settings.goals.goal.*).
  String get labelKey => switch (this) {
        Goal.lose => 'settings.goals.goal.lose',
        Goal.maintain => 'settings.goals.goal.maintain',
        Goal.gain => 'settings.goals.goal.gain',
      };
}

/// Cinsiyet (BMR hesabında other → male olarak ele alınır, web ile aynı).
enum Gender {
  male,
  female,
  other;

  String get labelKey => switch (this) {
        Gender.male => 'settings.personalInfo.male',
        Gender.female => 'settings.personalInfo.female',
        Gender.other => 'settings.personalInfo.other',
      };
}

/// Öğün tipleri (sıralama web ile aynı).
enum MealType {
  breakfast(1, '🌅'),
  lunch(2, '☀️'),
  dinner(3, '🌙'),
  snack(4, '🍎');

  const MealType(this.order, this.emoji);
  final int order;

  /// Web `MEAL_TYPES[type].icon` karşılığı.
  final String emoji;

  /// Şu anki saate göre mantıklı varsayılan öğün.
  ///
  /// `hour < 11` breakfast, `< 16` lunch, `< 21` dinner, else snack.
  /// Dashboard FAB'ın akla yakın bir öğün açması için kullanılır.
  static MealType defaultForNow() => defaultMealForHour(DateTime.now().hour);

  /// Saat eşiklerine göre varsayılan öğün — test edilebilir çekirdek.
  ///
  /// `@visibleForTesting`: [defaultForNow] bunu `DateTime.now().hour` ile
  /// çağırır. Eşikler: `< 11` breakfast, `< 16` lunch, `< 21` dinner, else
  /// snack.
  @visibleForTesting
  static MealType defaultMealForHour(int hour) {
    if (hour < 11) return MealType.breakfast;
    if (hour < 16) return MealType.lunch;
    if (hour < 21) return MealType.dinner;
    return MealType.snack;
  }
}
