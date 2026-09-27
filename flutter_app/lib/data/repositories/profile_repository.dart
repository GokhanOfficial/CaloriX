import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';

/// `profiles` tablosu CRUD — web `ProfileContext` karşılığı.
class ProfileRepository {
  ProfileRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'profiles';

  /// Kullanıcının profilini getirir (yoksa null).
  Future<Profile?> fetch(String userId) async {
    final data = await _client
        .from(_table)
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return null;
    return Profile.fromJson(data);
  }

  /// Profil alanlarını günceller (updated_at otomatik tazelenir).
  Future<Profile?> update(String userId, Map<String, dynamic> updates) async {
    final payload = {
      ...updates,
      // `timestamptz` kolonu → UTC damga (yerel saat kaymasını önler).
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final data = await _client
        .from(_table)
        .update(payload)
        .eq('id', userId)
        .select()
        .maybeSingle();
    if (data == null) return null;
    return Profile.fromJson(data);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

/// Oturum açık kullanıcının profili.
///
/// Oturum yoksa `null` döner; oturum değişince otomatik yenilenir.
/// UI tarafında `ref.watch(profileProvider)` kullanılır; güncelleme
/// sonrası taze veri için `ref.invalidate(profileProvider)` çağrılır.
final profileProvider = FutureProvider<Profile?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return ref.watch(profileRepositoryProvider).fetch(user.id);
});
