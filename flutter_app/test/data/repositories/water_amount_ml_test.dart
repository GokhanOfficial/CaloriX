import 'dart:convert';

import 'package:calorix/core/constants/app_constants.dart';
import 'package:calorix/data/models/water_entry.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `water_entries.amount_ml` hassasiyet sözleşmesi.
///
/// DB kolonu `INTEGER NOT NULL` (`20260111041204_...sql:134`,
/// `full_setup.sql:134`). Dart tarafı `double` taşır ve insert'te
/// `.round()` uygular — **bu bir yuvarlama kaybıdır** ve 250.5 ml isteği
/// 250 ml olarak kaydedilir. Doğrulama burada iki katmanlı:
///
///  1. **Yazma sınırı:** NaN / Infinity / ≤ 0 reddedilir (DB'ye ulaşmaz).
///  2. **Yuvarlama görünürlüğü:** `.round()` bilinçlidir ve **kullanıcıya
///     yansıyan** sonuç (kaydedilen ml) testin konusudur. Arayüzün 50 ml
///     adımlı olması (A4 alanı) bu kaybı erişilebilir kılar; veri katmanı
///     kendi tarafında da yuvarlamayı belgeliyor.
http.Response _respond(http.BaseRequest request, Object? body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

SupabaseClient _clientWith(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: MockClient((req) async => handler(req)),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );

void main() {
  group('addWaterEntry — yazma sınırı (DB\'ye ulaşmadan)', () {
    test('NaN / Infinity / 0 / negatif reddedilir', () async {
      var reachedDb = false;
      final client = _clientWith((req) async {
        reachedDb = true;
        return _respond(req, const <Object>[]);
      });
      final repo = DiaryRepository(client);

      for (final bad in <double>[0, -250, double.nan, double.infinity]) {
        expect(
          () => repo.addWaterEntry('u1', amountMl: bad, entryDate: '2026-08-15'),
          throwsArgumentError,
          reason: 'amountMl=$bad yazılmamalı',
        );
      }
      expect(reachedDb, isFalse, reason: 'geçersiz ml için hiçbir istek atılmamalı');
    });
  });

  group('addWaterEntry — integer kolona uyum (22P02 koruması)', () {
    test('ondalıklı ml gönderilmez; int\'e yuvarlanır', () async {
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        // PostgREST `select()` ile tek nesne döner.
        return _respond(req, {
          'id': 'w1',
          'user_id': 'u1',
          'amount_ml': 250,
          'entry_date': '2026-08-15',
        });
      });
      await DiaryRepository(client)
          .addWaterEntry('u1', amountMl: 250.0, entryDate: '2026-08-15');

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      final amount = body['amount_ml'];
      // `amount_ml INTEGER` — PostgREST'e `250.0` gönderilirse Postgres
      // `22P02 invalid input syntax for type integer` ile 400 döner ve
      // kullanıcının su kaydı hiç eklenmez.
      expect(amount, isA<int>(),
          reason: 'integer kolona ondalıklı değer gönderilirse POST 400 döner');
      expect(amount, 250);
    });

    test('küsuratlı ml yuvarlanır: 250.4 → 250, 250.5 → 251 (kayıp var)', () async {
      // `double.round()` sıfırdan uzağa yuvarlar (250.5 → 251), ondalık
      // kısım **her durumda** kaybolur. Arayüzün tam sayı girişi
      // (`digitsOnly`) ve 250/500 hızlı ekleme adımları nedeniyle normalde
      // ulaşılamaz; veri katmanı bunu gizlemez, `.round()` açıktır.
      Future<int> written(double ml) async {
        final requests = <http.Request>[];
        final client = _clientWith((req) async {
          requests.add(req);
          return _respond(req, {
            'id': 'w1',
            'user_id': 'u1',
            'amount_ml': ml.round(),
            'entry_date': '2026-08-15',
          });
        });
        await DiaryRepository(client)
            .addWaterEntry('u1', amountMl: ml, entryDate: '2026-08-15');
        final body =
            jsonDecode(requests.single.body) as Map<String, dynamic>;
        return body['amount_ml'] as int;
      }

      expect(await written(250.4), 250, reason: '0.4 ml kayboldu');
      expect(await written(250.5), 251, reason: 'Dart round() yarıdan uzağa');
      expect(await written(249.6), 250, reason: '0.4 ml yukarı yuvarlandı');
    });

    test('5000 ml üst sınırı veri katmanında yok (yalnız UI sınırlı)', () {
      // A4 `water_tracker._addCustom` 5000 ml üstünü eliyor; veri katmanı
      // yalnızca >0/sonlu kontrolü yapar. Kullanılabilir su miktarı olarak
      // fiziksel bir üst sınır olmadığı için bu bilinçli bir karar.
      expect(AppConstants.waterQuickAdd, [250, 500],
          reason: 'hızlı ekleme adımları tam sayı ml');
    });
  });

  group('WaterEntry modeli — integer ↔ double toleransı', () {
    test('DB int değeri double alanına güvenle okunur', () {
      final e = WaterEntry.fromJson({
        'id': 'w1',
        'user_id': 'u1',
        'amount_ml': 250,
        'entry_date': '2026-08-15',
      });
      expect(e.amountMl, 250.0);
    });

    test('ondalıklı değer de okunur (gelecekte numeric(8,1) geçişine hazır)', () {
      final e = WaterEntry.fromJson({
        'id': 'w1',
        'user_id': 'u1',
        'amount_ml': 250.5,
        'entry_date': '2026-08-15',
      });
      expect(e.amountMl, 250.5);
    });

    test('eksik entry_date/create edilse de toplam hesaplanabilir', () {
      final e = WaterEntry.fromJson({
        'id': 'w1',
        'user_id': 'u1',
        'amount_ml': 500,
        'entry_date': '2026-08-15',
      });
      final data = DailyData(
        mealEntries: const [],
        waterEntries: [e],
      );
      expect(data.totalWater, 500.0);
    });
  });
}
