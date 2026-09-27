import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_settings.dart';
import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';

/// `user_settings` tablosu — esnek anahtar/değer ayarları.
class UserSettingsRepository {
  UserSettingsRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'user_settings';

  /// Kullanıcının tüm ayarlarını `key → value` haritası olarak getirir.
  Future<Map<String, dynamic>> fetchAll(String userId) async {
    final rows = await _client.from(_table).select().eq('user_id', userId);
    final map = <String, dynamic>{};
    for (final row in rows as List) {
      final setting = UserSetting.fromJson(row as Map<String, dynamic>);
      map[setting.key] = setting.value;
    }
    return map;
  }

  /// Tek bir ayar değerini getirir (yoksa null).
  Future<dynamic> get(String userId, String key) async {
    final data = await _client
        .from(_table)
        .select('value')
        .eq('user_id', userId)
        .eq('key', key)
        .maybeSingle();
    return data?['value'];
  }

  /// Ayar yazar/günceller (upsert). `value` her türlü JSON olabilir.
  Future<void> set(String userId, String key, dynamic value) async {
    await _client.from(_table).upsert({
      'user_id': userId,
      'key': key,
      'value': value,
      // `timestamptz` kolonu → UTC damga (yerel saat kaymasını önler).
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,key');
  }
}

final userSettingsRepositoryProvider = Provider<UserSettingsRepository>((ref) {
  return UserSettingsRepository(ref.watch(supabaseClientProvider));
});

/// Oturum açık kullanıcının ayar haritası.
final userSettingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const {};
  return ref.watch(userSettingsRepositoryProvider).fetchAll(user.id);
});
