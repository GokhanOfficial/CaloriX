import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

/// Supabase istemcisi — uygulama genelinde tek instance.
///
/// NOT: Veritabanı şu an deaktif; canlı bağlantı testleri tüm fazlar
/// bittikten sonra yapılacak. İstemci yapılandırması eksikse (env boş)
/// uygulama yine de açılır, auth ekranı "yapılandırma eksik" uyarısı gösterir.
Future<void> initSupabase() async {
  if (!Env.isConfigured) return;
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // ignore: deprecated_member_use — anonKey web'in publishable key'iyle aynı değer
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
