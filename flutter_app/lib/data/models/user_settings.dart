import 'package:json_annotation/json_annotation.dart';

part 'user_settings.g.dart';

/// `user_settings` tablosu — anahtar/değer (key/value) saklayan esnek ayarlar.
/// `value` kolonu Json olduğundan burada dinamik tutulur.
@JsonSerializable()
class UserSetting {
  const UserSetting({
    required this.id,
    required this.userId,
    required this.key,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  @JsonKey(name: 'user_id')
  final String userId;

  final String key;

  /// Serbest biçimli JSON değer (bool, num, String, Map, List olabilir).
  final dynamic value;

  @JsonKey(name: 'created_at')
  final String createdAt;

  @JsonKey(name: 'updated_at')
  final String updatedAt;

  factory UserSetting.fromJson(Map<String, dynamic> json) =>
      _$UserSettingFromJson(json);

  Map<String, dynamic> toJson() => _$UserSettingToJson(this);
}
