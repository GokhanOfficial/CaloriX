import 'package:json_annotation/json_annotation.dart';

part 'water_entry.g.dart';

/// `water_entries` tablosu — web `useDailyData.WaterEntry` karşılığı.
@JsonSerializable()
class WaterEntry {
  const WaterEntry({
    required this.id,
    required this.userId,
    required this.amountMl,
    required this.entryDate,
    this.entryTime,
    this.createdAt,
    this.deletedAt,
  });

  final String id;

  @JsonKey(name: 'user_id')
  final String userId;

  @JsonKey(name: 'amount_ml')
  final double amountMl;

  /// `yyyy-MM-dd` formatında gün.
  @JsonKey(name: 'entry_date')
  final String entryDate;

  @JsonKey(name: 'entry_time')
  final String? entryTime;

  @JsonKey(name: 'created_at')
  final String? createdAt;

  @JsonKey(name: 'deleted_at')
  final String? deletedAt;

  factory WaterEntry.fromJson(Map<String, dynamic> json) =>
      _$WaterEntryFromJson(json);

  Map<String, dynamic> toJson() => _$WaterEntryToJson(this);
}
