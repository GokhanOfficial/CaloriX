import 'package:json_annotation/json_annotation.dart';

part 'weight_entry.g.dart';

/// `weight_entries` tablosu — web `useDailyData.WeightEntry` karşılığı.
@JsonSerializable()
class WeightEntry {
  const WeightEntry({
    required this.id,
    required this.userId,
    required this.weightKg,
    required this.entryDate,
    this.note,
    this.createdAt,
    this.deletedAt,
  });

  final String id;

  @JsonKey(name: 'user_id')
  final String userId;

  @JsonKey(name: 'weight_kg')
  final double weightKg;

  /// `yyyy-MM-dd` formatında gün.
  @JsonKey(name: 'entry_date')
  final String entryDate;

  final String? note;

  @JsonKey(name: 'created_at')
  final String? createdAt;

  @JsonKey(name: 'deleted_at')
  final String? deletedAt;

  factory WeightEntry.fromJson(Map<String, dynamic> json) =>
      _$WeightEntryFromJson(json);

  Map<String, dynamic> toJson() => _$WeightEntryToJson(this);
}
