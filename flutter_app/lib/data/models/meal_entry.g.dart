// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meal_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MealEntry _$MealEntryFromJson(Map<String, dynamic> json) => MealEntry(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  mealType: json['meal_type'] as String,
  amountGMl: (json['amount_g_ml'] as num).toDouble(),
  calculatedKcal: (json['calculated_kcal'] as num).toDouble(),
  calculatedProtein: (json['calculated_protein'] as num).toDouble(),
  calculatedCarbs: (json['calculated_carbs'] as num).toDouble(),
  calculatedFat: (json['calculated_fat'] as num).toDouble(),
  entryDate: json['entry_date'] as String,
  source: json['source'] as String,
  createdAt: json['created_at'] as String,
  foodId: json['food_id'] as String?,
  customName: json['custom_name'] as String?,
  note: json['note'] as String?,
  photoUrl: json['photo_url'] as String?,
  updatedAt: json['updated_at'] as String?,
  deletedAt: json['deleted_at'] as String?,
);

Map<String, dynamic> _$MealEntryToJson(MealEntry instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'food_id': instance.foodId,
  'custom_name': instance.customName,
  'meal_type': instance.mealType,
  'amount_g_ml': instance.amountGMl,
  'calculated_kcal': instance.calculatedKcal,
  'calculated_protein': instance.calculatedProtein,
  'calculated_carbs': instance.calculatedCarbs,
  'calculated_fat': instance.calculatedFat,
  'entry_date': instance.entryDate,
  'note': instance.note,
  'photo_url': instance.photoUrl,
  'source': instance.source,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
  'deleted_at': instance.deletedAt,
};
