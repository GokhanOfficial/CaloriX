// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'food.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FoodNutrition _$FoodNutritionFromJson(Map<String, dynamic> json) =>
    FoodNutrition(
      kcal: (json['kcal'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      carbsG: (json['carbs_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      fiberG: (json['fiber_g'] as num?)?.toDouble(),
      sugarG: (json['sugar_g'] as num?)?.toDouble(),
      saltG: (json['salt_g'] as num?)?.toDouble(),
      saturatedFatG: (json['saturated_fat_g'] as num?)?.toDouble(),
      transFatG: (json['trans_fat_g'] as num?)?.toDouble(),
      novaScore: (json['nova_score'] as num?)?.toInt(),
      nutriScore: json['nutri_score'] as String?,
      per100GMl: json['per_100_g_ml'] as bool?,
    );

Map<String, dynamic> _$FoodNutritionToJson(FoodNutrition instance) =>
    <String, dynamic>{
      'kcal': instance.kcal,
      'protein_g': instance.proteinG,
      'carbs_g': instance.carbsG,
      'fat_g': instance.fatG,
      'fiber_g': instance.fiberG,
      'sugar_g': instance.sugarG,
      'salt_g': instance.saltG,
      'saturated_fat_g': instance.saturatedFatG,
      'trans_fat_g': instance.transFatG,
      'nova_score': instance.novaScore,
      'nutri_score': instance.nutriScore,
      'per_100_g_ml': instance.per100GMl,
    };

Food _$FoodFromJson(Map<String, dynamic> json) => Food(
  id: json['id'] as String,
  name: json['name'] as String,
  brand: json['brand'] as String?,
  imageUrl: json['image_url'] as String?,
  servingSizeG: (json['serving_size_g'] as num?)?.toDouble(),
  servingDescription: json['serving_description'] as String?,
  source: json['source'] as String?,
  verified: json['verified'] as bool?,
  popularityCount: (json['popularity_count'] as num?)?.toInt(),
  nutrition: json['food_nutrition'] == null
      ? null
      : FoodNutrition.fromJson(json['food_nutrition'] as Map<String, dynamic>),
);

Map<String, dynamic> _$FoodToJson(Food instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'brand': instance.brand,
  'image_url': instance.imageUrl,
  'serving_size_g': instance.servingSizeG,
  'serving_description': instance.servingDescription,
  'source': instance.source,
  'verified': instance.verified,
  'popularity_count': instance.popularityCount,
  'food_nutrition': instance.nutrition,
};
