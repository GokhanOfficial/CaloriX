import 'package:json_annotation/json_annotation.dart';

part 'food.g.dart';

/// `food_nutrition` tablosu — `foods` ile 1:1 (food_id join).
/// Değerler `per_100_g_ml` olduğunda 100g başınadır (web'de hep öyle).
@JsonSerializable()
class FoodNutrition {
  const FoodNutrition({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.fiberG,
    this.sugarG,
    this.saltG,
    this.saturatedFatG,
    this.transFatG,
    this.novaScore,
    this.nutriScore,
    this.per100GMl,
  });

  final double kcal;

  @JsonKey(name: 'protein_g')
  final double proteinG;

  @JsonKey(name: 'carbs_g')
  final double carbsG;

  @JsonKey(name: 'fat_g')
  final double fatG;

  @JsonKey(name: 'fiber_g')
  final double? fiberG;

  @JsonKey(name: 'sugar_g')
  final double? sugarG;

  @JsonKey(name: 'salt_g')
  final double? saltG;

  @JsonKey(name: 'saturated_fat_g')
  final double? saturatedFatG;

  @JsonKey(name: 'trans_fat_g')
  final double? transFatG;

  @JsonKey(name: 'nova_score')
  final int? novaScore;

  @JsonKey(name: 'nutri_score')
  final String? nutriScore;

  @JsonKey(name: 'per_100_g_ml')
  final bool? per100GMl;

  factory FoodNutrition.fromJson(Map<String, dynamic> json) =>
      _$FoodNutritionFromJson(json);

  Map<String, dynamic> toJson() => _$FoodNutritionToJson(this);
}

/// `foods` tablosu — web `Food` tipi karşılığı.
@JsonSerializable()
class Food {
  const Food({
    required this.id,
    required this.name,
    this.brand,
    this.imageUrl,
    this.servingSizeG,
    this.servingDescription,
    this.source,
    this.verified,
    this.popularityCount,
    this.nutrition,
  });

  final String id;
  final String name;
  final String? brand;

  @JsonKey(name: 'image_url')
  final String? imageUrl;

  @JsonKey(name: 'serving_size_g')
  final double? servingSizeG;

  @JsonKey(name: 'serving_description')
  final String? servingDescription;

  final String? source;
  final bool? verified;

  @JsonKey(name: 'popularity_count')
  final int? popularityCount;

  /// Join ile gelen besin değerleri (`food_nutrition`).
  @JsonKey(name: 'food_nutrition')
  final FoodNutrition? nutrition;

  factory Food.fromJson(Map<String, dynamic> json) => _$FoodFromJson(json);

  Map<String, dynamic> toJson() => _$FoodToJson(this);
}
