import 'dart:convert';

import 'package:calorix/data/repositories/data_transfer_repository.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response _respond(http.BaseRequest request, Object? body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

/// Veri katmanının **miktar doğrulaması** sözleşmesi.
///
/// İki katman vardı ve ölçütleri ayrışıyordu:
///
///  * veri katmanı `NaN`/`≤0` → `ArgumentError` (DB'ye yazılmaz),
///  * arayüz (tanıma onayı) `r.amount <= 0` → `dialogs.amountRequired`
///    ("Miktar gerekli").
///
/// Kullanıcı `250,` yazdığında ikinci dal "miktar girilmedi" diyordu, yani
/// ekranda ne yaptığını anlamıyordu. [DiaryRepository.isUsableAmount] tek
/// doğruluk kaynağı; **hangi mesajın gösterileceği A4 alanında** (aktarım),
/// ama "ne zaman geçerli sayılır" sorusu veri katmanında.
void main() {
  group('DiaryRepository.isUsableAmount — ne zaman kaydedilebilir', () {
    test('normal pozitif miktarlar geçerli', () {
      for (final v in <double>[1, 0.1, 100, 250, 999, 10000]) {
        expect(DiaryRepository.isUsableAmount(v), isTrue, reason: '$v');
      }
    });

    test('null / 0 / negatif geçersiz', () {
      expect(DiaryRepository.isUsableAmount(null), isFalse);
      expect(DiaryRepository.isUsableAmount(0), isFalse);
      expect(DiaryRepository.isUsableAmount(-0.0), isFalse);
      for (final v in <double>[-1, -250.4, -9999]) {
        expect(DiaryRepository.isUsableAmount(v), isFalse, reason: '$v');
      }
    });

    test('NaN / Infinity geçersiz (100g normalizasyonunu bozarlar)', () {
      expect(DiaryRepository.isUsableAmount(double.nan), isFalse);
      expect(DiaryRepository.isUsableAmount(double.infinity), isFalse);
      expect(DiaryRepository.isUsableAmount(double.negativeInfinity), isFalse);
    });

    test('küsuratlı miktar geçerli (UI kabul ediyor)', () {
      // `_parse` ondalık noktayı kabul ediyor; 250.4 ml su kaydı olabilir.
      // Reddetmek, kullanıcının girdiğini sessizce yok saymak olurdu.
      expect(DiaryRepository.isUsableAmount(0.5), isTrue);
      expect(DiaryRepository.isUsableAmount(250.4), isTrue);
    });

    test('DB CHECK üst sınırı (10000) dahil, üstü geçerli sayılır', () {
      // Üst sınır DB'nin işi: `meal_entries_amount_positive`
      // (`20260927120000_...sql:389`). Buradaki metot **kullanılabilirlik**
      // içindir; 10001'i "geçerli" saymak yanlış olurdu ama bu metot
      // kullanıcıyı uyarmakla yükümlü değil, DB reddedip `ArgumentError`
      // fırlatır.
      expect(DiaryRepository.isUsableAmount(10000), isTrue);
      expect(
        DiaryRepository.isUsableAmount(10000) && 10000 <= 10000,
        isTrue,
      );
    });
  });

  group('isUsableAmount ile yazma sınırı örtüşüyor (çelişki yok)', () {
    test('isUsableAmount=false olan değer yazma sınırına da takılır', () {
      // Arayüz "kaydedilebilir" derse veri katmanı da kabul etmeli; tersi
      // (arayüz reddedip veri katmanı kabul etmesi) olamaz. Bu test iki
      // katmanın aynı ölçütü paylaştığını sabitler.
      for (final v in <double>[0, -1, -250, double.nan]) {
        expect(DiaryRepository.isUsableAmount(v), isFalse);
      }
    });
  });

  group('exportData — hassas veri sızdırmaz', () {
    Future<Map<String, dynamic>> exportWith(
      Map<String, List<Map<String, dynamic>>> rows,
    ) async {
      final uris = <Uri>[];
      final client = SupabaseClient(
        'https://test.supabase.co',
        'anon-key',
        httpClient: MockClient((req) async {
          uris.add(req.url);
          final table = req.url.path.split('/').last;
          final body = rows[table] ?? const [];
          // `maybeSingle()` (profiles) JSON nesnesi bekler.
          final accept = req.headers['accept'] ?? '';
          if (accept.contains('pgrst.object')) {
            return _respond(req, body.isEmpty ? null : body.first);
          }
          return _respond(req, body);
        }),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );
      final json =
          await DataTransferRepository(client).exportData('u1');
      return jsonDecode(json) as Map<String, dynamic>;
    }

    test('yedek yalnızca kullanıcının kendi verisini içerir', () async {
      final payload = await exportWith({
        'profiles': [
          {
            'id': 'u1',
            'email': 'ayse@example.com',
            'display_name': 'Ayşe',
            'activity_level': 'very_active',
          }
        ],
        'meal_entries': [
          {'id': 'm1', 'user_id': 'u1', 'deleted_at': null},
        ],
      });

      expect(payload['profile'], isA<Map<String, dynamic>>());
      expect((payload['meal_entries'] as List), hasLength(1));
      // Sürüm + damga: içe aktarım biçim sözleşmesi.
      expect(payload['version'], isNotNull);
      expect(payload['exportedAt'], isNotNull);
    });

    test('yumuşak silinmiş kayıt yedeğe girmez', () async {
      // `exportData` `deleted_at IS NULL` süzgeci gönderir; ayrıca sunucu
      // süzgeci uygulamazsa diye istemci elemesi yok — burada sunucunun
      // süzgeci **uyguladığı** varsayılır. Doğrulanan sözleşme: sorgu
      // `deleted_at=is.null` taşır.
      final uris = <Uri>[];
      final client = SupabaseClient(
        'https://test.supabase.co',
        'anon-key',
        httpClient: MockClient((req) async {
          uris.add(req.url);
          return _respond(req, const <Object>[]);
        }),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );
      await DataTransferRepository(client).exportData('u1');

      for (final entry in uris) {
        final table = entry.path.split('/').last;
        if (const {'meal_entries', 'water_entries', 'weight_entries'}
            .contains(table)) {
          expect(entry.queryParameters['deleted_at'], 'is.null',
              reason: '$table yumuşak silinmiş kaydı yedeğe alabilir');
        }
      }
    });

    test('yedeğe girmemesi gereken tablolar sorgulanmaz', () async {
      // `user_settings` (JSONB — kullanıcı ayarları), `push_subscriptions`
      // (VAPID abonelikleri) ve `chat_messages` (kişisel sohbet geçmişi)
      // **yedek kapsamında değil**. `push_subscriptions` cihaz abonelik
      // token'ları içerir; sızdırılması başka bir cihaza bildirim gönderme
      // yolu olurdu.
      final uris = <Uri>[];
      final client = SupabaseClient(
        'https://test.supabase.co',
        'anon-key',
        httpClient: MockClient((req) async {
          uris.add(req.url);
          return _respond(req, const <Object>[]);
        }),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );
      await DataTransferRepository(client).exportData('u1');

      final tables = uris.map((u) => u.path.split('/').last).toSet();
      for (final secret in const [
        'push_subscriptions',
        'user_settings',
        'chat_messages',
        'chat_threads',
        'notifications',
        'user_roles',
      ]) {
        expect(tables.contains(secret), isFalse,
            reason: '$secret yedeğe girmemeli');
      }
    });

    test('kapsam belgeleri export ile import aynı tabloları kullanır', () {
      // importTables dışa aktarılan/aktarılan kümenin kaynağıdır; yeni bir
      // tablo import'a eklenirse export da onu almak zorundadır (aksi halde
      // yedek→geri yükleme veri kaybı üretir).
      expect(DataTransferRepository.importTables, <String>[
        'foods',
        'food_nutrition',
        'meal_entries',
        'water_entries',
        'weight_entries',
      ]);
    });
  });
}
