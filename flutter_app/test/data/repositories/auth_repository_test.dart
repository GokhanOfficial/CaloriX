import 'package:calorix/data/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AuthRepository repo;

  setUpAll(() {
    registerFallbackValue(OtpType.signup);
    registerFallbackValue(UserAttributes());
  });

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    repo = AuthRepository(client);
  });

  group('AuthRepository.signIn', () {
    test('başarılı girişte null döner', () async {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => AuthResponse(session: null, user: null));

      final err = await repo.signIn('a@b.com', 'secret1');

      expect(err, isNull);
      verify(
        () => auth.signInWithPassword(email: 'a@b.com', password: 'secret1'),
      ).called(1);
    });

    test('AuthException fırlatılırsa aynen döner', () async {
      const exception = AuthException('Invalid login credentials');
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(exception);

      final err = await repo.signIn('a@b.com', 'wrong');

      expect(err, isNotNull);
      expect(err!.message, 'Invalid login credentials');
    });
  });

  group('AuthRepository.signUp', () {
    test('displayName verilince data içinde gönderilir', () async {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => AuthResponse(session: null, user: null));

      final err = await repo.signUp('a@b.com', 'secret1', displayName: 'Gokhan');

      expect(err, isNull);
      verify(
        () => auth.signUp(
          email: 'a@b.com',
          password: 'secret1',
          emailRedirectTo: any(named: 'emailRedirectTo'),
          data: {'display_name': 'Gokhan'},
        ),
      ).called(1);
    });

    test('displayName yoksa e-posta öneki kullanılır (web parity)', () async {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => AuthResponse(session: null, user: null));

      await repo.signUp('jane.doe@example.com', 'secret1');

      verify(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
          data: {'display_name': 'jane.doe'},
        ),
      ).called(1);
    });

    test('redirect URL deep link şemasını içerir (test = VM, web değil)', () async {
      String? captured;
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
          data: any(named: 'data'),
        ),
      ).thenAnswer((inv) async {
        captured = inv.namedArguments[#emailRedirectTo] as String?;
        return AuthResponse(session: null, user: null);
      });

      await repo.signUp('a@b.com', 'secret1');

      expect(captured, 'io.supabase.calorix://reset-callback/auth?verified=true');
    });

    test('"User already registered" hatası aynen döner', () async {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
          data: any(named: 'data'),
        ),
      ).thenThrow(const AuthException('User already registered'));

      final err = await repo.signUp('a@b.com', 'secret1');

      expect(err?.message, 'User already registered');
    });
  });

  group('AuthRepository.resetPassword', () {
    test('redirectTo deep link içerir', () async {
      String? captured;
      when(
        () => auth.resetPasswordForEmail(
          any(),
          redirectTo: any(named: 'redirectTo'),
        ),
      ).thenAnswer((inv) async {
        captured = inv.namedArguments[#redirectTo] as String?;
      });

      final err = await repo.resetPassword('a@b.com');

      expect(err, isNull);
      expect(captured, 'io.supabase.calorix://reset-callback/auth?reset=true');
    });

    test('hata durumunda AuthException döner', () async {
      when(
        () => auth.resetPasswordForEmail(
          any(),
          redirectTo: any(named: 'redirectTo'),
        ),
      ).thenThrow(const AuthException('Rate limit exceeded'));

      final err = await repo.resetPassword('a@b.com');

      expect(err?.message, 'Rate limit exceeded');
    });
  });

  group('AuthRepository.resendVerificationEmail', () {
    test('oturum/e-posta yoksa hata döner (çağrı yapılmaz)', () async {
      when(() => auth.currentUser).thenReturn(null);

      final err = await repo.resendVerificationEmail();

      expect(err?.message, 'No email found');
      verifyNever(
        () => auth.resend(
          type: any(named: 'type'),
          email: any(named: 'email'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      );
    });

    test('kullanıcı varsa OtpType.signup ile yeniden gönderir', () async {
      when(() => auth.currentUser).thenReturn(
        User(
          id: 'u1',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          email: 'a@b.com',
          createdAt: DateTime(2026).toIso8601String(),
        ),
      );
      when(
        () => auth.resend(
          type: any(named: 'type'),
          email: any(named: 'email'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      ).thenAnswer((_) async => ResendResponse());

      final err = await repo.resendVerificationEmail();

      expect(err, isNull);
      verify(
        () => auth.resend(
          type: OtpType.signup,
          email: 'a@b.com',
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      ).called(1);
    });
  });

  group('AuthRepository.updatePassword', () {
    test('yeni şifre UserAttributes ile gönderilir', () async {
      when(() => auth.updateUser(any())).thenAnswer(
        (_) async => UserResponse.fromJson({
          'id': 'u1',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
          'aud': 'authenticated',
          'created_at': DateTime(2026).toIso8601String(),
        }),
      );

      final err = await repo.updatePassword('yeni-sifre-123');

      expect(err, isNull);
      final captured = verify(() => auth.updateUser(captureAny())).captured;
      expect((captured.single as UserAttributes).password, 'yeni-sifre-123');
    });
  });

  group('AuthRepository.signOut', () {
    test('GoTrueClient.signOut çağrılır', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});

      await repo.signOut();

      verify(() => auth.signOut()).called(1);
    });
  });

  group('AuthRepository.isEmailVerified', () {
    test('kullanıcı yoksa false', () {
      when(() => auth.currentUser).thenReturn(null);
      expect(repo.isEmailVerified, isFalse);
    });

    test('emailConfirmedAt doluysa true', () {
      when(() => auth.currentUser).thenReturn(
        User(
          id: 'u1',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime(2026).toIso8601String(),
          emailConfirmedAt: DateTime(2026, 2).toIso8601String(),
        ),
      );
      expect(repo.isEmailVerified, isTrue);
    });
  });
}
