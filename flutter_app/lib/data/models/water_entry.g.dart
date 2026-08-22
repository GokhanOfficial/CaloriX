// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'water_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WaterEntry _$WaterEntryFromJson(Map<String, dynamic> json) => WaterEntry(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  amountMl: (json['amount_ml'] as num).toDouble(),
  entryDate: json['entry_date'] as String,
  entryTime: json['entry_time'] as String?,
  createdAt: json['created_at'] as String?,
  deletedAt: json['deleted_at'] as String?,
);

Map<String, dynamic> _$WaterEntryToJson(WaterEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'amount_ml': instance.amountMl,
      'entry_date': instance.entryDate,
      'entry_time': instance.entryTime,
      'created_at': instance.createdAt,
      'deleted_at': instance.deletedAt,
    };
