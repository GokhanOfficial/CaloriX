// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Profile _$ProfileFromJson(Map<String, dynamic> json) => Profile(
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
  activityLevel: json['activity_level'] as String?,
  goal: json['goal'] as String?,
  bmr: (json['bmr'] as num?)?.toDouble(),
  tdee: (json['tdee'] as num?)?.toDouble(),
  dailyCalorieTarget: (json['daily_calorie_target'] as num?)?.toDouble(),
  proteinTargetG: (json['protein_target_g'] as num?)?.toDouble(),
  carbsTargetG: (json['carbs_target_g'] as num?)?.toDouble(),
  fatTargetG: (json['fat_target_g'] as num?)?.toDouble(),
  dailyWaterTargetMl: (json['daily_water_target_ml'] as num?)?.toDouble(),
  weighInFrequencyDays: (json['weigh_in_frequency_days'] as num?)?.toInt(),
  pushNotificationsEnabled: json['push_notifications_enabled'] as bool?,
  emailNotificationsEnabled: json['email_notifications_enabled'] as bool?,
  onboardingCompleted: json['onboarding_completed'] as bool?,
  autoRecalculateMacros: json['auto_recalculate_macros'] as bool?,
  timezone: json['timezone'] as String?,
);

Map<String, dynamic> _$ProfileToJson(Profile instance) => <String, dynamic>{
  'id': instance.id,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
  'display_name': instance.displayName,
  'email': instance.email,
  'avatar_url': instance.avatarUrl,
  'birth_date': instance.birthDate,
  'gender': instance.gender,
  'height_cm': instance.heightCm,
  'current_weight_kg': instance.currentWeightKg,
  'target_weight_kg': instance.targetWeightKg,
  'activity_level': instance.activityLevel,
  'goal': instance.goal,
  'bmr': instance.bmr,
  'tdee': instance.tdee,
  'daily_calorie_target': instance.dailyCalorieTarget,
  'protein_target_g': instance.proteinTargetG,
  'carbs_target_g': instance.carbsTargetG,
  'fat_target_g': instance.fatTargetG,
  'daily_water_target_ml': instance.dailyWaterTargetMl,
  'weigh_in_frequency_days': instance.weighInFrequencyDays,
  'push_notifications_enabled': instance.pushNotificationsEnabled,
  'email_notifications_enabled': instance.emailNotificationsEnabled,
  'onboarding_completed': instance.onboardingCompleted,
  'auto_recalculate_macros': instance.autoRecalculateMacros,
  'timezone': instance.timezone,
};
