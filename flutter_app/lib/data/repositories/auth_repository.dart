import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client_provider.dart';

/// Web `AuthContext.tsx`'in Dart karşılığı.
///
/// Tüm auth işlemleri `SupabaseClient.auth` üzerinden geçer.
/// Hata döndürme biçimi web ile aynı: `{ error }` benzeri nullable `AuthException?`.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// Mevcut oturum kullanıcısı (yoksa null).
  User? get currentUser => _auth.currentUser;

  /// Mevcut oturum (yoksa null).
  Session? get currentSession => _auth.currentSession;

  /// Auth durum değişiklikleri (giriş/çıkış/token yenileme/PASSWORD_RECOVERY).
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  bool get isEmailVerified => currentUser?.emailConfirmedAt != null;

  /// Kayıt — doğrulama e-postası için redirect URL web ile aynı mantıkta.
  Future<AuthException?> signUp(
    String email,
    String password, {
    String? displayName,
  }) async {
    try {
      await _auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: _emailRedirect('/auth?verified=true'),
        data: {'display_name': displayName ?? email.split('@').first},
      );
      return null;
    } on AuthException catch (e) {
      return e;
    }
  }

  /// Giriş.
  Future<AuthException?> signIn(String email, String password) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
      return null;
    } on AuthException catch (e) {
      return e;
    }
  }

  /// Çıkış.
  Future<void> signOut() => _auth.signOut();

  /// Şifre sıfırlama e-postası — deep link redirect.
  Future<AuthException?> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(
        email,
        redirectTo: _emailRedirect('/auth?reset=true'),
      );
      return null;
    } on AuthException catch (e) {
      return e;
    }
  }

  /// Doğrulama e-postasını yeniden gönder.
  Future<AuthException?> resendVerificationEmail() async {
    final email = currentUser?.email;
    if (email == null) {
      return const AuthException('No email found');
    }
    try {
      await _auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: _emailRedirect('/auth?verified=true'),
      );
      return null;
    } on AuthException catch (e) {
      return e;
    }
  }

  /// Yeni şifre belirle (PASSWORD_RECOVERY sonrası).
  Future<AuthException?> updatePassword(String newPassword) async {
    try {
      await _auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      return e;
    }
  }

  /// Platform bazlı e-posta redirect URL'i.
  ///
  /// Web'de mevcut origin kullanılır; mobilde deep link şeması.
  String? _emailRedirect(String path) {
    if (kIsWeb) {
      // Web: origin + path (query korunur)
      return '${Uri.base.origin}$path';
    }
    // Android/iOS: deep link — manifest intent-filter ile eşleşmeli.
    return 'io.supabase.calorix://reset-callback$path';
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

/// Auth durumunu stream olarak yayınlar (router redirect bunu dinler).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

/// Oturum açık kullanıcı (null = misafir).
final currentUserProvider = Provider<User?>((ref) {
  // authStateProvider değişince yeniden hesaplanır.
  final authState = ref.watch(authStateProvider).valueOrNull;
  return authState?.session?.user ??
      ref.watch(authRepositoryProvider).currentUser;
});

/// PASSWORD_RECOVERY eventi geldiğinde true olur.
final passwordRecoveryProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(authRepositoryProvider)
      .authStateChanges
      .map((s) => s.event == AuthChangeEvent.passwordRecovery)
      .where((e) => e);
});
