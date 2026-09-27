import 'package:calorix/core/observability/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

/// Release modunda Sentry'ye giden log mesajları PII içermemeli.
///
/// `main.dart` `sendDefaultPii = false` ile Sentry'nin **otomatik** PII
/// toplamasını kapatıyor; ancak uygulama log satırları (`AppLog.w/e`) elle
/// yazıldığı için bu satırlar otomatik süzgeçten geçmez.
void main() {
  group('scrubPii — maskelenmesi gerekenler', () {
    test('e-posta adresi', () {
      expect(
        AppLog.scrubPii('Giriş başarısız: lance@example.com'),
        'Giriş başarısız: [redacted]',
      );
    });

    test('Bearer token', () {
      expect(
        AppLog.scrubPii('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def'),
        contains('[redacted]'),
      );
      expect(
        AppLog.scrubPii('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def'),
        isNot(contains('eyJhbGciOiJIUzI1NiJ9')),
      );
    });

    test('JWT benzeri üç parçalı token', () {
      const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxIn0.abcdEFGH1234';
      final out = AppLog.scrubPii('token=$jwt');
      expect(out, isNot(contains(jwt)));
    });

    test('Supabase anon/service anahtarı (uzun eyJ...)', () {
      const key =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6InRlc3Qta2V5LWlk'
          'In0.QQQQQWWWWWEEEEEERRRRRTTTTYYYYY';
      final out = AppLog.scrubPii('SUPABASE_ANON_KEY=$key');
      expect(out, isNot(contains(key)));
    });

    test('parola/apikey değişken atamaları', () {
      expect(AppLog.scrubPii('password=s3cr3t!'), contains('[redacted]'));
      expect(AppLog.scrubPii('api_key: abcdef123'), contains('[redacted]'));
      expect(AppLog.scrubPii('parola = 1234'), contains('[redacted]'));
      expect(AppLog.scrubPii('anon_key=xyz'), contains('[redacted]'));
    });

    test('32+ karakterlik hex (sha256/token) maskesi', () {
      const sha = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      final out = AppLog.scrubPii('sha256=$sha');
      expect(out, isNot(contains(sha)));
      expect(out, contains('[redacted:64]'));
    });
  });

  group('scrubPii — dokunulmaması gerekenler', () {
    test('normal hata mesajı aynen kalır', () {
      const msg = 'Güncelleme manifesti alınamadı, cache\'e dönülüyor';
      expect(AppLog.scrubPii(msg), msg);
    });

    test('kısa sayısal değerler maskelenmez', () {
      const msg = 'build 4 < minSupported 7 (HTTP 503)';
      expect(AppLog.scrubPii(msg), msg);
    });

    test('boş string', () {
      expect(AppLog.scrubPii(''), '');
    });

    test('JSON günlük satırı olduğu gibi kalır (yapı bozulmaz)', () {
      const msg = '{"status":503,"count":2}';
      expect(AppLog.scrubPii(msg), msg);
    });
  });

  group('ScrubbedError', () {
    test('toString temizlenmiş metni döner', () {
      const e = ScrubbedError('[redacted]');
      expect(e.toString(), '[redacted]');
      expect(e, isA<Exception>());
    });
  });
}
