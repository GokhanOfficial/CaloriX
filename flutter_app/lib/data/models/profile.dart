import 'package:json_annotation/json_annotation.dart';

part 'profile.g.dart';

/// `profiles` tablosu — web `ProfileContext.UserProfile` karşılığı.
/// Alan adları Supabase (snake_case) ile birebir eşleşir.
@JsonSerializable()
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
  });

  final String id;

  @JsonKey(name: 'created_at')
  final String createdAt;

  @JsonKey(name: 'updated_at')
  final String updatedAt;

  @JsonKey(name: 'display_name')
  final String? displayName;

  final String? email;

  @JsonKey(name: 'avatar_url')
  final String? avatarUrl;

  @JsonKey(name: 'birth_date')
  final String? birthDate;

  final String? gender;

  @JsonKey(name: 'height_cm')
  final double? heightCm;

  @JsonKey(name: 'current_weight_kg')
  final double? currentWeightKg;

  @JsonKey(name: 'target_weight_kg')
  final double? targetWeightKg;

  @JsonKey(name: 'activity_level')
  final String? activityLevel;

  final String? goal;

  final double? bmr;

  final double? tdee;

  @JsonKey(name: 'daily_calorie_target')
  final double? dailyCalorieTarget;

  @JsonKey(name: 'protein_target_g')
  final double? proteinTargetG;

  @JsonKey(name: 'carbs_target_g')
  final double? carbsTargetG;

  @JsonKey(name: 'fat_target_g')
  final double? fatTargetG;

  @JsonKey(name: 'daily_water_target_ml')
  final double? dailyWaterTargetMl;

  @JsonKey(name: 'weigh_in_frequency_days')
  final int? weighInFrequencyDays;

  @JsonKey(name: 'push_notifications_enabled')
  final bool? pushNotificationsEnabled;

  @JsonKey(name: 'email_notifications_enabled')
  final bool? emailNotificationsEnabled;

  @JsonKey(name: 'onboarding_completed')
  final bool? onboardingCompleted;

  @JsonKey(name: 'auto_recalculate_macros')
  final bool? autoRecalculateMacros;

  final String? timezone;

  factory Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileToJson(this);

  /// Onboarding akışının tamamlanıp tamamlanmadığı.
  bool get isOnboardingComplete => onboardingCompleted ?? false;

  Profile copyWith({
    String? displayName,
    String? birthDate,
    String? gender,
    double? heightCm,
    double? currentWeightKg,
    double? targetWeightKg,
    String? activityLevel,
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
    );
  }
}
