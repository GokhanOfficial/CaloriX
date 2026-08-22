import 'package:json_annotation/json_annotation.dart';

part 'meal_entry.g.dart';

/// `meal_entries` tablosu — web `useDailyData.MealEntry` karşılığı.
///
/// `foodId` null ise kullanıcının manuel/özel girdisidir (`customName`).
/// Besin değerleri giriş anında `calculated_*` alanlarına yazılır
/// (amount değişse bile web'de de böyle saklanır).
@JsonSerializable()
class MealEntry {
  const MealEntry({
    required this.id,
    required this.userId,
    required this.mealType,
    required this.amountGMl,
    required this.calculatedKcal,
    required this.calculatedProtein,
    required this.calculatedCarbs,
    required this.calculatedFat,
    required this.entryDate,
    required this.source,
    required this.createdAt,
    this.foodId,
    this.customName,
    this.note,
    this.photoUrl,
    this.updatedAt,
    this.deletedAt,
  });

  final String id;

  @JsonKey(name: 'user_id')
  final String userId;

  @JsonKey(name: 'food_id')
  final String? foodId;

  @JsonKey(name: 'custom_name')
  final String? customName;

  /// `meal_type` enum: breakfast | lunch | dinner | snack
  @JsonKey(name: 'meal_type')
  final String mealType;

  @JsonKey(name: 'amount_g_ml')
  final double amountGMl;

  @JsonKey(name: 'calculated_kcal')
  final double calculatedKcal;

  @JsonKey(name: 'calculated_protein')
  final double calculatedProtein;

  @JsonKey(name: 'calculated_carbs')
  final double calculatedCarbs;

  @JsonKey(name: 'calculated_fat')
  final double calculatedFat;

  /// `yyyy-MM-dd` formatında gün.
  @JsonKey(name: 'entry_date')
  final String entryDate;

  final String? note;

  @JsonKey(name: 'photo_url')
  final String? photoUrl;

  /// `food_source` enum: photo | text | manual
  final String source;

  @JsonKey(name: 'created_at')
  final String createdAt;

  @JsonKey(name: 'updated_at')
  final String? updatedAt;

  @JsonKey(name: 'deleted_at')
  final String? deletedAt;

  factory MealEntry.fromJson(Map<String, dynamic> json) =>
      _$MealEntryFromJson(json);

  Map<String, dynamic> toJson() => _$MealEntryToJson(this);

  /// Görüntüleme adı — join yoksa custom_name fallback'i (web: "Bilinmeyen").
  String get displayName => customName ?? 'Bilinmeyen';
}
