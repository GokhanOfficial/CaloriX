/// 2026-10-17 — sağlayıcı doygunluğuna karşı tek seferlik sessiz yeniden deneme.
///
/// ## Bu test neden var?
///
/// Canlı ölçüm (bkz. `.superpowers/sdd/KALAN-ISLER/progress.md`): AI
/// sağlayıcısının vision yolu doygunluk pencerelerinde isteklerin ~%40'ını
/// 60-74 s beklettikten sonra ret ediyor → edge fonksiyonu
/// `502 "AI servisi şu anda yanıt vermiyor"` döndürüyor. Retler kısa
/// pencereli olduğundan `RecognitionRepository` **bir kez** sessiz yeniden
/// deniyor; ikinci ret kullanıcıya taşınıyor.
///
/// Sözleşme (kilitlenen davranış):
/// 1. `502` → **bir kez** yeniden denenir; ikinci deneme başarılıysa
///    sonuç normal akışta döner (kullanıcı hata görmez).
/// 2. `429` (rate limit) → aynı şekilde bir kez yeniden denenir.
/// 3. `400`/`401` gibi deterministik hatalar → **yeniden deneme yok**
///    (anlamsız bekleme; hata anında yukarı taşınır).
/// 4. Yeniden deneme de ret yerse → `RecognitionException` fırlatılır
///    ve mesaj sunucudan gelen `{error}` metnidir.
library;

import 'dart:convert';

import 'package:calorix/data/repositories/recognition_repository.dart';
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

SupabaseClient _clientWith(
  Future<http.Response> Function(http.Request) handler,
) =>
    SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: MockClient((req) async => handler(req)),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );

/// `recognize-food` invoke'una verilen yanıtlar sırayla tüketilir.
///
/// `functions.invoke` POST atar; listenin eleman sayısı kadar çağrı gelir,
/// fazlası testi patlatır (fazla deneme = sözleşme ihlali).
SupabaseClient _clientWithSequence(List<http.Response> responses) {
  var i = 0;
  return _clientWith((req) async {
    expect(req.method, 'POST', reason: 'invoke POST atar');
    expect(req.url.path, contains('functions/v1/'), reason: 'edge invoke yolu');
    if (i >= responses.length) {
      fail('beklenenden fazla istek atıldı (${i + 1}.): retry sözleşmesi '
          'tek deneme eklemeli, sonsuz döngü olmamalı');
    }
    return responses[i++];
  });
}

const _okBody = {
  'foods': [
    {
      'name': 'Elma',
      'amount_g_ml': 150,
      'calories_per_100g': 52,
      'protein_g_per_100g': 0.3,
      'carbs_g_per_100g': 13.8,
      'fat_g_per_100g': 0.2,
      'nova_score': 1,
      'nutri_score': 'A',
      'confidence': 90,
    }
  ],
  'description': 'tek elma',
};

const _errBody = {'error': 'AI servisi şu anda yanıt vermiyor'};

void main() {
  group('1) 502 — sağlayıcı doygunluğu', () {
    test('ilk 502 + ikinci deneme 200 → sonuç döner, istemci hata görmez',
        () async {
      final client = _clientWithSequence([
        _respond(client0req, _errBody, status: 502),
        _respond(client0req, _okBody),
      ]);

      final result =
          await RecognitionRepository(client).recognizeFoodText('1 elma');

      expect(result.foods, hasLength(1));
      expect(result.foods.first.name, 'Elma');
    });

    test('iki 502 → hata taşınır (sonsuz deneme yok)', () async {
      final client = _clientWithSequence([
        _respond(client0req, _errBody, status: 502),
        _respond(client0req, _errBody, status: 502),
      ]);

      await expectLater(
        RecognitionRepository(client).recognizeFoodText('1 elma'),
        throwsA(isA<RecognitionException>().having(
          (e) => e.message,
          'message',
          contains('AI servisi'),
        )),
      );
    });
  });

  group('2) 429 — rate limit aynı yoldan', () {
    test('429 + 200 → tek yeniden deneme yeter', () async {
      final client = _clientWithSequence([
        _respond(client0req, {'error': 'Çok fazla istek'}, status: 429),
        _respond(client0req, _okBody),
      ]);

      final result =
          await RecognitionRepository(client).recognizeFoodText('1 elma');
      expect(result.foods, hasLength(1));
    });
  });

  group('3) deterministik hatalar — yeniden deneme yok', () {
    test('400 → anında hata, ikinci istek atılmaz', () async {
      final client = _clientWithSequence([
        _respond(client0req, {'error': 'Eksik veya geçersiz istek'}, status: 400),
      ]);

      await expectLater(
        RecognitionRepository(client).recognizeFoodText(''),
        throwsA(isA<RecognitionException>()),
      );
    });

    test('401 → anında hata, ikinci istek atılmaz', () async {
      final client = _clientWithSequence([
        _respond(client0req, {'error': 'Yetkisiz'}, status: 401),
      ]);

      await expectLater(
        RecognitionRepository(client).recognizeFoodText('1 elma'),
        throwsA(isA<RecognitionException>()),
      );
    });
  });
}

/// MockClient handler'ında request nesnesine ihtiyaç var; sabit bir istek
/// referansı için yardımcı (yanıt `request` alanını taşımalı).
http.Request get client0req => _dummyRequest;
final http.Request _dummyRequest = http.Request('POST', Uri.parse('https://test.supabase.co/functions/v1/recognize-food-text'));
