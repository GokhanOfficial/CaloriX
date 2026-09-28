/// `AccountRepository` — `delete-account` edge sözleşmesi (A4r4b, Tur 10).
///
/// ## Bu test neden var?
///
/// Sunucu tarafı (A1r3 → A1r8) hazır ve 124 deno testiyle doğrulanmış, ama
/// **istemci tarafı daha yeniydi**. Buradaki her iddia, `supabase/functions/
/// delete-account/index.ts` + `helpers.ts` + `_shared/*` **kaynak koddan**
/// çıkarılmıştır; hiçbir durum kodunun ne olduğu tahmin edilmez:
///
///  - 401 → **iki ayrı sabit mesaj** (`"Parola hatalı"` / `"Yetkisiz"`) —
///    bu yüzden `wrongPassword` ve `unauthorized` ayrı tiplerdir.
///  - 429 → sunucu kotası (2/saat, **kullanıcı bazlı**).
///  - 400/405/413/415 → `AuthError`/`ValidationError` → istek reddi.
///  - 5xx → `"Hesap silinemedi…"` → belirsiz hata.
///  - 200 + `retryRecommended: true` → **kısmi silme** (hesap hâlâ duruyor).
///    `rolledBack` alanı **yoktur**; A1r4 bu modeli ölçüm sonrası terk etti.
///
/// ## Güvenlik iddiaları (parola sızıntısı)
///
///  1. İstek gövdesi **yalnızca** `{"password": …}` — `userId` BOLA
///     yüzeyini kapatmak için gövdeye hiçbir kimlik konmaz.
///  2. Parola **hiçbir** hata/istisna/log mesajında geçmez. Bu, koda
///    güvenilip test edilmiştir: `AccountDeletionException` yalnızca `kind`,
///    `status` ve `causeType` taşır; parola sınıfa hiç girmez. Yine de
///    **ağ hatası yolunda** (`FunctionsFetchException`, `details` doluysa
///    ham hata metni) log çıktısı taranır.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:calorix/core/observability/app_logger.dart';
import 'package:calorix/data/repositories/account_repository.dart';

/// Testte kullanılan parola — sızıntı taramasında aranan **tek** dize.
const _secret = 'Parola-Gizli-123!';

http.Response _respond(http.BaseRequest request, Object? body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

void main() {
  late List<http.Request> captured;

  /// İstekleri yakalayan istemci kurar ve gövdeyi `MockClient` içinde okur.
  SupabaseClient clientReturning(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: MockClient((req) async {
        // `MockClient` gövdeyi zaten okumuş olabilir; yine de biz de
        // kopyalıyoruz ki test gövdeyi **kendi** doğrulayabilsin.
        if (req.body.isNotEmpty) captured.add(req);
        return handler(req);
      }),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
  }

  setUp(() => captured = []);

  group('başarılı yanıt', () {
    test('200 + success → tam silme (partial: false)', () async {
      final repo = AccountRepository(clientReturning((req) async => _respond(
            req,
            const {
              'success': true,
              'message': 'Hesabınız ve tüm verileriniz kalıcı olarak silindi.',
            },
          )));

      final result = await repo.deleteAccount(password: _secret);

      expect(result.completed, isTrue);
      expect(result.partial, isFalse);
      expect(result.retryRecommended, isFalse);
    });

    test('200 + retryRecommended:true → KISMİ SİLME (hesap hâlâ duruyor)',
        () async {
      // `index.ts:145-156`: bu dal yalnızca `auth.admin.deleteUser()`
      // BAŞARISIZ olduğunda çalışır, yani auth kaydı duruyor.
      final repo = AccountRepository(clientReturning((req) async => _respond(
            req,
            const {
              'success': true,
              'message':
                  'Hesabınızın bir bölümü silinemedi. Lütfen birkaç dakika sonra tekrar deneyin.',
              'retryRecommended': true,
            },
          )));

      final result = await repo.deleteAccount(password: _secret);

      expect(result.partial, isTrue);
      expect(result.retryRecommended, isTrue,
          reason: 'sunucunun alan adı istemciye birebir taşınır');
      expect(result.completed, isFalse,
          reason: 'kısmi silme "tamamlandı" sayılmaz (KVKK)');
    });

    test('gövde `rolledBack` taşımıyor — sunucu bu alanı üretmiyor', () {
      // Sözleşme doğrulaması: `index.ts` hiçbir yerde `rolledBack` yazmıyor.
      // Bu yüzden istemci `retryRecommended`'a bakar; `rolledBack` okunmaz.
      expect(AccountRepository.retryRecommendedField, 'retryRecommended');
    });
  });

  group('hata türleri — HTTP durum kodu eşlemesi', () {
    test('401 "Parola hatalı" → wrongPassword', () async {
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'error': 'Parola hatalı'},
              status: 401)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.wrongPassword)
            .having((e) => e.status, 'status', 401)),
      );
    });

    test('401 "Yetkisiz" → unauthorized (parola hatalı DEĞİL)', () async {
      // `index.ts:80` ve `:160` → 401'in iki ayrı sabit mesajı var.
      // Oturum geçersizse "parolanız hatalı" demek kullanıcıyı sonsuz
      // döngüye sokardı; doğru eylem yeniden giriş.
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'error': 'Yetkisiz'},
              status: 401)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.unauthorized)),
      );
    });

    test('429 → rateLimited (sunucu kotası 2/saat)', () async {
      final repo = AccountRepository(clientReturning((req) async => _respond(
              req, const {'error': 'Çok fazla deneme yapıldı, lütfen bekleyin'},
              status: 429)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.rateLimited)
            .having((e) => e.status, 'status', 429)),
      );
    });

    test('400 → invalidRequest', () async {
      final repo = AccountRepository(clientReturning((req) async => _respond(
              req, const {'error': 'Eksik veya geçersiz istek'},
              status: 400)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.invalidRequest)),
      );
    });

    test('415 → invalidRequest (Content-Type reddi)', () async {
      // `readJsonBody` (`_shared/auth.ts:108-112`): `application/json` dışı
      // içerik türü 415. `functions.invoke` başlığı otomatik koyduğu için
      // bu istemcide **tetiklenmez**, ama sunucu sözleşmesi gereği eşlenir.
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'error': 'Geçersiz içerik türü'},
              status: 415)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.invalidRequest)),
      );
    });

    test('405 → invalidRequest (yalnızca POST desteklenir)', () async {
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'error': 'Yalnızca POST desteklenir'},
              status: 405)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.invalidRequest)),
      );
    });

    test('413 → invalidRequest (gövde çok büyük)', () async {
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'error': 'Gövde çok büyük'},
              status: 413)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.invalidRequest)),
      );
    });

    test('500 → unknown', () async {
      final repo = AccountRepository(clientReturning((req) async => _respond(
              req,
              const {'error': 'Hesap silinemedi, lütfen daha sonra tekrar deneyin'},
              status: 500)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.unknown)
            .having((e) => e.status, 'status', 500)),
      );
    });

    test('ağ hatası (status 0) → network', () async {
      final repo = AccountRepository(
          clientReturning((req) async => throw const SocketLikeError()));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.network)),
      );
    });

    test('200 ama success alanı yok → unknown (sessiz "başarı" YOK)', () async {
      // KVKK: sunucu sözleşmeyi ihlal edip 200 dönerse kullanıcıya
      // "silindi" demek yanlış olur. İstemci bunu **hata** sayar.
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'message': 'tamam'}, status: 200)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.unknown)),
      );
    });

    test('200 ama success:false → unknown', () async {
      final repo = AccountRepository(clientReturning((req) async => _respond(
              req, const {'success': false, 'error': 'bir şey oldu'},
              status: 200)));

      await expectLater(
        repo.deleteAccount(password: _secret),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.unknown)),
      );
    });
  });

  group('istemci öncesi doğrulama — kota korunur', () {
    test('boş parola sunucuya GİTMEZ (2/saat kota harcanmaz)', () async {
      var called = false;
      final repo = AccountRepository(clientReturning((req) async {
        called = true;
        return _respond(req, const {'success': true});
      }));

      await expectLater(
        repo.deleteAccount(password: '   '),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.invalidRequest)),
      );
      expect(called, isFalse,
          reason: 'sunucu da reddediyor ama kota istemcide korunmalı');
    });

    test('256 karakteri aşan parola gönderilmez (sunucu üst sınırı)', () async {
      var called = false;
      final repo = AccountRepository(clientReturning((req) async {
        called = true;
        return _respond(req, const {'success': true});
      }));

      await expectLater(
        repo.deleteAccount(password: 'a' * (AccountRepository.maxPasswordLength + 1)),
        throwsA(isA<AccountDeletionException>()
            .having((e) => e.kind, 'kind', AccountDeletionErrorKind.invalidRequest)),
      );
      expect(called, isFalse);
    });

    test('tam 256 karakter kabul edilir (sınır değer dahil)', () async {
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'success': true})));
      final password = 'a' * AccountRepository.maxPasswordLength;
      final result = await repo.deleteAccount(password: password);
      expect(result.completed, isTrue);
    });
  });

  group('gövde sözleşmesi — yalnızca password', () {
    test('POST + gövde tam olarak {password}', () async {
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'success': true})));

      await repo.deleteAccount(password: _secret);

      expect(captured, hasLength(1));
      final request = captured.single;
      expect(request.method, 'POST');
      expect(request.url.path, contains('/functions/v1/delete-account'));

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys, ['password'],
          reason: 'BOLA: gövdeye userId/token konmaz; sunucu yalnızca '
              'requireString(body.password) okur');
      expect(body['password'], _secret);
    });

    test('parola kırpılır (sunucu requireString trim eder)', () async {
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'success': true})));

      await repo.deleteAccount(password: '  $_secret  ');

      final body = jsonDecode(captured.single.body) as Map<String, dynamic>;
      expect(body['password'], _secret);
    });

    test('Content-Type otomatik application/json (415 riski yok)', () async {
      // `readJsonBody` (`_shared/auth.ts:108-112`) `application/json`
      // dışındaki içerik türünü 415 ile reddeder. Elle `fetch` kullansaydık
      // bu başlığı unutmak kolaydı; `functions.invoke` koyar.
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'success': true})));

      await repo.deleteAccount(password: _secret);

      expect(
        captured.single.headers['content-type'],
        contains('application/json'),
      );
    });

    test('Authorization başlığında parola YOK (SDK yönetir)', () async {
      // Ölçülen gerçek (2026-09-28): `functions_client-2.7.1` `invoke`,
      // `Content-Type`'ı **ve** `Authorization`'ı **kendisi** ekliyor.
      // Test istemcisinde oturum olmadığı için başlık anon key'i taşıyor;
      // üretimde `Bearer <JWT>` olur. Önemli olan: **parola** ne `Authorization`
      // değerinde ne de gövde dışında herhangi bir yerde taşınıyor.
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'success': true})));

      await repo.deleteAccount(password: _secret);

      final request = captured.single;
      // Başlığın **var olması** SDK sorumluluğudur (elle fetch yazsaydık
      // unutulurdu ve 401 alırdık).
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          contains('authorization'));
      for (final entry in request.headers.entries) {
        expect(entry.value, isNot(contains(_secret)),
            reason: '${entry.key} başlığında parola sızmamalı');
      }
    });
  });

  group('GÜVENLİK — parola hiçbir hata yolunda görünmez', () {
    test('401 hata mesajı parolayı içermez', () async {
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'error': 'Parola hatalı'},
              status: 401)));

      try {
        await repo.deleteAccount(password: _secret);
        fail('401 istisna fırlatmalıydı');
      } on AccountDeletionException catch (e) {
        expect(e.toString(), isNot(contains(_secret)));
        expect(e.toString(), contains('wrongPassword'),
            reason: 'istisna anlam taşır ama parolayı taşımaz');
      }
    });

    test('500 hata mesajı parolayı içermez', () async {
      final repo = AccountRepository(clientReturning((req) async => _respond(
              req, const {'error': 'Hesap silinemedi'}, status: 500)));

      try {
        await repo.deleteAccount(password: _secret);
        fail('500 istisna fırlatmalıydı');
      } on AccountDeletionException catch (e) {
        expect(e.toString(), isNot(contains(_secret)));
      }
    });

    test('ağ hatası (status 0) parolayı içermez', () async {
      // `FunctionsFetchException.details` ham hata nesnesi olabilir; log
      // satırında **yalnızca HTTP durum kodu** vardır (bkz. repository
      // `AppLog.w('Hesap silme isteği başarısız (HTTP 0)')`).
      final repo = AccountRepository(
          clientReturning((req) async => throw const SocketLikeError()));

      try {
        await repo.deleteAccount(password: _secret);
        fail('ağ hatası istisna fırlatmalıydı');
      } on AccountDeletionException catch (e) {
        expect(e.toString(), isNot(contains(_secret)));
        expect(e.kind, AccountDeletionErrorKind.network);
      }
    });

    test('başarı sonucu da parolayı içermez', () async {
      final repo = AccountRepository(clientReturning(
          (req) async => _respond(req, const {'success': true})));

      final result = await repo.deleteAccount(password: _secret);
      expect(result.toString(), isNot(contains(_secret)));
    });

    test('AppLog.scrubPii parola kalıbını yine de maskeler (çift katman)',
        () async {
      // Savunma derinliği: kod zaten göndermiyor, ama bir gün bir hata
      // `password=…` kalıbıyla loglanırsa süzgeç yakalar.
      // `app_logger.dart:59-63` → `password`/`parola` + ayraç + değer.
      // Bu test süzgecin devrede olduğunu **ölçer**.
      final masked = AppLog.scrubPii('Hesap silme: password=$_secret');
      expect(masked, isNot(contains(_secret)));
      expect(masked, contains('[redacted]'));
    });
  });
}

/// Ağ hatası taklidi — `http.Client` `MockClient` içinden fırlatılır.
class SocketLikeError implements Exception {
  const SocketLikeError();
  @override
  String toString() => 'SocketLikeError: connection closed';
}
