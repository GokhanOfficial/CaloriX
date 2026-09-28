import '../../core/constants/app_constants.dart';
import '../activity_level_map.dart';

/// `profiles` tablosu — web `ProfileContext.UserProfile` karşılığı.
/// Alan adları Supabase (snake_case) ile birebir eşleşir.
///
/// `activity_level` **türlü** olduğu için `json_serializable` **kullanılmaz**:
/// üretilen kod `json['activity_level'] as ActivityLevel?` yazardı ve (a)
/// derlenmezdi, (b) tanımsız DB değerinde **istisna fırlatırdı**. Elle yazılan
/// [fromJson] toleranslıdır ([ActivityLevelMap.fromDb]) ve
/// [rawActivityLevel]'ı korur.
class Profile {
  const Profile({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.displayName,
    this.email,
    this.avatarUrl,
    this.birthDate,
    this.gender,
    this.heightCm,
    this.currentWeightKg,
    this.targetWeightKg,
    this.activityLevel,
    this.goal,
    this.bmr,
    this.tdee,
    this.dailyCalorieTarget,
    this.proteinTargetG,
    this.carbsTargetG,
    this.fatTargetG,
    this.dailyWaterTargetMl,
    this.weighInFrequencyDays,
    this.pushNotificationsEnabled,
    this.emailNotificationsEnabled,
    this.onboardingCompleted,
    this.autoRecalculateMacros,
    this.timezone,
    this.rawActivityLevel,
  });

  final String id;

  final String createdAt;

  final String updatedAt;

  final String? displayName;

  final String? email;

  final String? avatarUrl;

  final String? birthDate;

  final String? gender;

  final double? heightCm;

  final double? currentWeightKg;

  final double? targetWeightKg;

  /// `profiles.activity_level` — **türlü** ([ActivityLevel]).
  ///
  /// DB kısıtı (`full_setup.sql:38`):
  /// `CHECK (activity_level IN ('sedentary','light','moderate','active',
  /// 'very_active'))`.
  ///
  /// ## Neden enum (TDEE sapması)
  ///
  /// Alan önce `String?` idi ve okuma noktaları elle
  /// `activityLevelFromDb(...)` çağırıyordu. CHECK kısıtı üç ayrı yerde
  /// yeniden yorumlanıyordu ve **`very_active` sessizce `moderate` (1.55)
  /// sayılıyordu** — 30y/erkek/175cm/80kg için doğru olan 3382 kcal yerine
  /// 2759 kcal (%18,4 eksik) makro hedefi yazılıyordu. Ayrıca
  /// `ActivityLevel.veryActive.name` (`'veryActive'`) CHECK'i ihlal eder ve
  /// profil UPDATE'i başarısız olurdu.
  ///
  /// Artık:
  ///  * **Yazma türle güvence altında**: `copyWith(activityLevel: …)`
  ///    `ActivityLevel` kabul eder; `'veryActive'` gibi bir dize **derlenmez**.
  ///    DB'ye yazma `activityLevelToDb` ile olur.
  ///  * **Okuma çökmez**: [ActivityLevelMap.fromDb] bozuk/tanımsız bir DB
  ///    değerini [ActivityLevelMap.fallback]'e düşürür ve loglar.
  ///
  /// `null` kalabilir (onboarding tamamlanmamış profil).
  ///
  /// **Ham DB değeri** [rawActivityLevel] içinde korunur — yedek ve teşhis
  /// için gereklidir ("kullanıcının DB'de ne yazdığı" sorusunun cevabı).
  /// `toJson()` **kanonik** CHECK değerini yazar; böylece Flutter'dan alınan
  /// bir yedek web istemcisine de aktarılabilir.
  final ActivityLevel? activityLevel;

  final String? goal;

  final double? bmr;

  final double? tdee;

  final double? dailyCalorieTarget;

  final double? proteinTargetG;

  final double? carbsTargetG;

  final double? fatTargetG;

  final double? dailyWaterTargetMl;

  final int? weighInFrequencyDays;

  final bool? pushNotificationsEnabled;

  final bool? emailNotificationsEnabled;

  final bool? onboardingCompleted;

  final bool? autoRecalculateMacros;

  final String? timezone;

  /// DB'den gelen **ham** `activity_level` dizesi — CHECK kısıtında olmayan
  /// bir değer olabilir (elle yazılmış veri, yeni sunucu sürümü, eski
  /// istemcinin `veryActive` yazımı).
  ///
  /// Yedek içe aktarımı ve teşhis için saklanır; **mantıkta kullanılmaz** —
  /// mantık [activityLevel] kullanır.
  final String? rawActivityLevel;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final raw = json['activity_level'];
    // `null` korunur (onboarding tamamlanmamış); dolu ama tanımsız değer
    // fallback'e düşer ve loglanır (`activityLevelFromDb` çökmez).
    final parsed = raw == null ? null : ActivityLevelMap.fromDb(raw);
    return Profile(
      id: json['id'] as String,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      displayName: json['display_name'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      birthDate: json['birth_date'] as String?,
      gender: json['gender'] as String?,
      heightCm: (json['height_cm'] as num?)?.toDouble(),
      currentWeightKg: (json['current_weight_kg'] as num?)?.toDouble(),
      targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
      activityLevel: parsed,
      goal: json['goal'] as String?,
      bmr: (json['bmr'] as num?)?.toDouble(),
      tdee: (json['tdee'] as num?)?.toDouble(),
      dailyCalorieTarget: (json['daily_calorie_target'] as num?)?.toDouble(),
      proteinTargetG: (json['protein_target_g'] as num?)?.toDouble(),
      carbsTargetG: (json['carbs_target_g'] as num?)?.toDouble(),
      fatTargetG: (json['fat_target_g'] as num?)?.toDouble(),
      dailyWaterTargetMl: (json['daily_water_target_ml'] as num?)?.toDouble(),
      weighInFrequencyDays: (json['weigh_in_frequency_days'] as num?)?.toInt(),
      pushNotificationsEnabled:
          json['push_notifications_enabled'] as bool?,
      emailNotificationsEnabled:
          json['email_notifications_enabled'] as bool?,
      onboardingCompleted: json['onboarding_completed'] as bool?,
      autoRecalculateMacros: json['auto_recalculate_macros'] as bool?,
      timezone: json['timezone'] as String?,
      rawActivityLevel: raw?.toString(),
    );
  }

  /// `activity_level` **kanonik** DB değerini yazar (`activityLevelToDb`).
  ///
  /// Ham değer **bilerek yazılmaz**: bir yedek başka bir istemciye (web)
  /// aktarıldığında da CHECK kısıtında kalmalıdır; ham değer tanımsızsa
  /// içe aktarma zaten reddedilirdi.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'display_name': displayName,
        'email': email,
        'avatar_url': avatarUrl,
        'birth_date': birthDate,
        'gender': gender,
        'height_cm': heightCm,
        'current_weight_kg': currentWeightKg,
        'target_weight_kg': targetWeightKg,
        'activity_level': activityLevel == null
            ? null
            : ActivityLevelMap.toDb(activityLevel!),
        'goal': goal,
        'bmr': bmr,
        'tdee': tdee,
        'daily_calorie_target': dailyCalorieTarget,
        'protein_target_g': proteinTargetG,
        'carbs_target_g': carbsTargetG,
        'fat_target_g': fatTargetG,
        'daily_water_target_ml': dailyWaterTargetMl,
        'weigh_in_frequency_days': weighInFrequencyDays,
        'push_notifications_enabled': pushNotificationsEnabled,
        'email_notifications_enabled': emailNotificationsEnabled,
        'onboarding_completed': onboardingCompleted,
        'auto_recalculate_macros': autoRecalculateMacros,
        'timezone': timezone,
      };

  /// Onboarding akışının tamamlanıp tamamlanmadığı.
  bool get isOnboardingComplete => onboardingCompleted ?? false;

  Profile copyWith({
    String? displayName,
    String? birthDate,
    String? gender,
    double? heightCm,
    double? currentWeightKg,
    double? targetWeightKg,
    ActivityLevel? activityLevel,
    String? goal,
    double? bmr,
    double? tdee,
    double? dailyCalorieTarget,
    double? proteinTargetG,
    double? carbsTargetG,
    double? fatTargetG,
    double? dailyWaterTargetMl,
    bool? onboardingCompleted,
  }) {
    return Profile(
      id: id,
      createdAt: createdAt,
      updatedAt: updatedAt,
      displayName: displayName ?? this.displayName,
      email: email,
      avatarUrl: avatarUrl,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      currentWeightKg: currentWeightKg ?? this.currentWeightKg,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      activityLevel: activityLevel ?? this.activityLevel,
      goal: goal ?? this.goal,
      bmr: bmr ?? this.bmr,
      tdee: tdee ?? this.tdee,
      dailyCalorieTarget: dailyCalorieTarget ?? this.dailyCalorieTarget,
      proteinTargetG: proteinTargetG ?? this.proteinTargetG,
      carbsTargetG: carbsTargetG ?? this.carbsTargetG,
      fatTargetG: fatTargetG ?? this.fatTargetG,
      dailyWaterTargetMl: dailyWaterTargetMl ?? this.dailyWaterTargetMl,
      weighInFrequencyDays: weighInFrequencyDays,
      pushNotificationsEnabled: pushNotificationsEnabled,
      emailNotificationsEnabled: emailNotificationsEnabled,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      autoRecalculateMacros: autoRecalculateMacros,
      timezone: timezone,
      rawActivityLevel: rawActivityLevel,
    );
  }
}
