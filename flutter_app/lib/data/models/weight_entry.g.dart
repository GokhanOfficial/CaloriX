// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weight_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WeightEntry _$WeightEntryFromJson(Map<String, dynamic> json) => WeightEntry(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  weightKg: (json['weight_kg'] as num).toDouble(),
  entryDate: json['entry_date'] as String,
  note: json['note'] as String?,
  createdAt: json['created_at'] as String?,
  deletedAt: json['deleted_at'] as String?,
);

Map<String, dynamic> _$WeightEntryToJson(WeightEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'weight_kg': instance.weightKg,
      'entry_date': instance.entryDate,
      'note': instance.note,
      'created_at': instance.createdAt,
      'deleted_at': instance.deletedAt,
    };
