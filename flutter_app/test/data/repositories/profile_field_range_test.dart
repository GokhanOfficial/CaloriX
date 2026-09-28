import 'dart:convert';

import 'package:calorix/data/repositories/profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `ProfileRepository.update` alan sınırı savunması (A2r9).
///
/// ## Neden bu test var?
///
/// A1r8 (Tur 8) `profiles` tablosuna beş aralık CHECK'i ekledi
/// (`supabase/migrations/20260928400000_data_integrity_check_constraints.sql`):
/// `height_cm` 100-250, `current/target_weight_kg` 20-500,
/// `daily_water_target_ml` 0-10000, `weigh_in_frequency_days` 1-365.
///
/// DB CHECK'i **yazma anında** çalışır ve `23514` döner. Ama Flutter'da beş
/// ayrı ekran `ProfileRepository.update` çağırıyor ve **hepsi `catch (_)`
/// ile yutuyor** → kullanıcı "Kaydedildi" görür, hiçbir şey yazılmamıştır.
/// En kötü hali: `notifications_dialog.dart:146`
/// `int.tryParse(...) ?? 7` ile metin kutusuna yazılan `-5` **her seferinde**
/// `check-reminders`'ı tetikliyordu.
///
/// Savunma veri katmanında: aralık dışı değer **hiçbir istek atılmadan**
/// `ProfileFieldRangeError` ile reddedilir.
void main() {
  group('1) Saf doğrulama (ağ yok) — kabul edilen değerler', () {
    test('aralık içi değerler geçer', () {
      expect(
        () => ProfileRepository.validateField('weigh_in_frequency_days', 7),
        returnsNormally,
      );
      expect(
        () => ProfileRepository.validateField('weigh_in_frequency_days', 1),
        returnsNormally,
        reason: 'alt sınır',
      );
      expect(
        () => ProfileRepository.validateField('weigh_in_frequency_days', 365),
        returnsNormally,
        reason: 'üst sınır',
      );
      expect(
        () => ProfileRepository.validateField('height_cm', 180.5),
        returnsNormally,
      );
      expect(
        () => ProfileRepository.validateField('height_cm', 100),
        returnsNormally,
      );
      expect(
        () => ProfileRepository.validateField('daily_water_target_ml', 0),
        returnsNormally,
        reason: 'su hedefinde 0 geçerli (CHECK `0 … 10000`)',
      );
    });

    test('null her zaman geçerli — CHECK\'ler `IS NULL OR …` biçiminde', () {
      for (final field in ProfileRepository.fieldRanges.keys) {
        expect(
          () => ProfileRepository.validateField(field, null),
          returnsNormally,
          reason: '$field nullable (onboarding tamamlanmamış profil)',
        );
      }
    });

    test('sınırsız alanlar dokunulmadan geçer', () {
      for (final value in <Object?>[999999, -1, 'abc', double.nan]) {
        expect(
          () => ProfileRepository.validateField('display_name', value),
          returnsNormally,
        );
        expect(
          () => ProfileRepository.validateField('goal', value),
          returnsNormally,
        );
      }
      expect(ProfileRepository.hasRange('display_name'), isFalse);
      expect(ProfileRepository.hasRange('weigh_in_frequency_days'), isTrue);
    });
  });

  group('2) ⭐ A1r8\'in bulgusu: negatif tartma sıklığı', () {
    test('-5 reddedilir (check-reminders\'ta HER koşuda tetiklenirdi)', () {
      expect(
        () => ProfileRepository.validateField('weigh_in_frequency_days', -5),
        throwsA(isA<ProfileFieldRangeError>()),
      );
    });

    test('0 reddedilir (CHECK alt sınırı 1)', () {
      expect(
        () => ProfileRepository.validateField('weigh_in_frequency_days', 0),
        throwsA(isA<ProfileFieldRangeError>()),
      );
    });

    test('366 reddedilir (CHECK üst sınırı 365)', () {
      expect(
        () => ProfileRepository.validateField('weigh_in_frequency_days', 366),
        throwsA(isA<ProfileFieldRangeError>()),
      );
    });

    test('hata "7" yazdıysa "30" yazmaz — değer **korunmaz**, hata verir', () {
      try {
        ProfileRepository.validateField('weigh_in_frequency_days', -5);
        fail('hata fırlatmalıydı');
      } on ProfileFieldRangeError catch (e) {
        expect(e.field, 'weigh_in_frequency_days');
        expect(e.value, -5);
        expect(e.range, '1-365 gün');
        expect(e.summary, contains('1-365 gün'));
        // Sunucu/şema sızıntısı yok: kısıt adı ya da kolon listesi taşınmaz.
        expect(e.summary, isNot(contains('CHECK')));
        expect(e.summary, isNot(contains('profiles_')));
      }
    });
  });

  group('3) Diğer CHECK aralıkları', () {
    test('boy 99 / 251 reddedilir (fiziksel olmayan)', () {
      for (final h in <num>[99, 99.9, 250.1, 3000, -180]) {
        expect(
          () => ProfileRepository.validateField('height_cm', h),
          throwsA(isA<ProfileFieldRangeError>()),
          reason: 'height_cm=$h',
        );
      }
    });

    test('kilo 19.9 / 500.1 reddedilir', () {
      for (final w in <num>[19.9, 500.1, 0, -70]) {
        expect(
          () => ProfileRepository.validateField('current_weight_kg', w),
          throwsA(isA<ProfileFieldRangeError>()),
          reason: 'current_weight_kg=$w',
        );
        expect(
          () => ProfileRepository.validateField('target_weight_kg', w),
          throwsA(isA<ProfileFieldRangeError>()),
          reason: 'target_weight_kg=$w',
        );
      }
    });

    test('su hedefi 10001 ve negatif reddedilir', () {
      for (final w in <num>[10001, -1, 1e9]) {
        expect(
          () => ProfileRepository.validateField('daily_water_target_ml', w),
          throwsA(isA<ProfileFieldRangeError>()),
          reason: 'daily_water_target_ml=$w',
        );
      }
    });

    test('NaN / Infinity reddedilir (JSON 400 + Postgres ayrıştırma hatası)', () {
      for (final v in <num>[double.nan, double.infinity, double.negativeInfinity]) {
        expect(
          () => ProfileRepository.validateField('daily_water_target_ml', v),
          throwsA(isA<ProfileFieldRangeError>()),
          reason: '$v',
        );
      }
    });

    test('sayı olmayan değer reddedilir (Postgres 22P02)', () {
      for (final v in <Object>['7', true, <int>[7]]) {
        expect(
          () => ProfileRepository.validateField('weigh_in_frequency_days', v),
          throwsA(isA<ProfileFieldRangeError>()),
          reason: '${v.runtimeType}',
        );
      }
    });
  });

  group('4) validateUpdates — tüm gövde tek seferde denetlenir', () {
    test('bir alan geçersizse gövde reddedilir', () {
      expect(
        () => ProfileRepository.validateUpdates({
          'push_notifications_enabled': true,
          'weigh_in_frequency_days': -5,
          'auto_recalculate_macros': false,
        }),
        throwsA(isA<ProfileFieldRangeError>()),
      );
    });

    test('birden çok sınırlı alan sırayla denetlenir, ilk ihlal bildirilir', () {
      expect(
        () => ProfileRepository.validateUpdates({
          'height_cm': 3000,
          'weigh_in_frequency_days': -5,
        }),
        throwsA(isA<ProfileFieldRangeError>()
            .having((e) => e.field, 'field', 'height_cm')),
      );
    });

    test('null değerli sınırlı alanlar geçer (temizleme yolu)', () {
      expect(
        () => ProfileRepository.validateUpdates({
          'height_cm': null,
          'current_weight_kg': null,
          'weigh_in_frequency_days': null,
        }),
        returnsNormally,
      );
    });
  });

  group('5) ⭐ update() — reddedilen alanda HİÇBİR istek atılmaz', () {
    test('negatif sıklık: PATCH hiç gitmez, "kaydedildi" yalanı söylenmez', () async {
      final calls = <http.Request>[];
      final client = _client(calls);
      final repo = ProfileRepository(client);

      await expectLater(
        repo.update('u1', {'weigh_in_frequency_days': -5}),
        throwsA(isA<ProfileFieldRangeError>()),
      );
      expect(calls, isEmpty, reason: 'yarım yazma olmamalı');
    });

    test('onboarding\'in geçersiz boyu: hiçbir yazma yok', () async {
      final calls = <http.Request>[];
      final repo = ProfileRepository(_client(calls));

      await expectLater(
        repo.update('u1', {
          'display_name': 'Test',
          'height_cm': 3000.0,
          'current_weight_kg': 70.0,
        }),
        throwsA(isA<ProfileFieldRangeError>()),
      );
      expect(calls, isEmpty);
    });

    test('geçerli güncelleme: tek PATCH, updated_at UTC damgalı', () async {
      final calls = <http.Request>[];
      final repo = ProfileRepository(_client(calls));

      final profile = await repo.update('u1', {
        'weigh_in_frequency_days': 14,
        'daily_water_target_ml': 2640,
      });

      expect(profile, isNotNull);
      expect(profile!.weighInFrequencyDays, 14);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'PATCH');
      final body = jsonDecode(calls.single.body) as Map<String, dynamic>;
      expect(body['weigh_in_frequency_days'], 14);
      expect(body['updated_at'], endsWith('Z'),
          reason: 'timestamptz → UTC');
    });
  });
}

/// Gerçek `SupabaseClient` + sahte HTTP katmanı. `_respond` `request`i
/// ilişkisel korur (postgrest `_parseResponse` bunu okuyor).
SupabaseClient _client(List<http.Request> calls) {
  return SupabaseClient(
    'https://test.supabase.co',
    'anon-key',
    httpClient: MockClient((req) async {
      calls.add(req);
      return http.Response(
        jsonEncode({
          'id': 'u1',
          'created_at': '2026-01-01T00:00:00+00:00',
          'updated_at': '2026-01-02T00:00:00+00:00',
          'weigh_in_frequency_days': 14,
          'daily_water_target_ml': 2640,
        }),
        200,
        headers: {'content-type': 'application/json'},
        request: req,
      );
    }),
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
  );
}
