// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserSetting _$UserSettingFromJson(Map<String, dynamic> json) => UserSetting(
  id: json['id'] as String,
  userId: json['user_id'] as String,
  key: json['key'] as String,
  value: json['value'],
  createdAt: json['created_at'] as String,
  updatedAt: json['updated_at'] as String,
);

Map<String, dynamic> _$UserSettingToJson(UserSetting instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'key': instance.key,
      'value': instance.value,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };
