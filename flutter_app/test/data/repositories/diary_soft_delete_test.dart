import 'dart:convert';

import 'package:calorix/data/repositories/analytics_repository.dart';
import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `postgrest` yanıtı `response.request` alanını okur (`_parseResponse`,
/// postgrest_builder.dart:462); null ise `Null check operator used on a null
/// value` fırlatır. `MockClient` isteği yanıtta **taşımaz** — bu sarmalayıcı
/// ilişkiyi geri kurar.
http.Response _respond(http.BaseRequest request, Object? body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

/// Gerçek `SupabaseClient` + sahte HTTP katmanı.
///
/// Bu yaklaşım mock zincirinden daha güçlü: **gerçek** PostgREST URL'i
/// üretilir ve gerçek filtreleme uygulanır; ağ yerine `MockClient` yanıt
/// verir. "Hangi filtre gitti?" sorusu zincir kurmadan yanıtlanır.
SupabaseClient _clientWith(Future<http.Response> Function(http.Request) handler) =>
    SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: MockClient((req) async => handler(req)),
      // Yeniden deneme kapalı: testlerde beklemeden hata dönmeli.
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );

/// Yumuşak silme (soft delete) sözleşmesi.
///
/// Kritik soru: **silinen kayıt toplamlara giriyor mu?**
/// `meal_entries` / `water_entries` / `weight_entries` tablolarında
/// `deleted_at` kolonu var
/// (`supabase/migrations/20260111041204_...sql:141/159/171`) ve üç tabloda da
/// **fiziksel silme yolu yoktur** — `DiaryRepository` yalnızca `deleted_at`
/// damgası yazar. Bu testler her okuma yolunun `deleted_at IS NULL` filtresi
/// taşıdığını ve geri almanın gerçekten çalıştığını kanıtlar.
void main() {
  group('fetchDaily — her sorgu deleted_at IS NULL taşır', () {
    late List<Uri> uris;
    late Map<String, List<Map<String, dynamic>>> rows;
    late DiaryRepository repo;

    setUp(() {
      uris = <Uri>[];
      rows = {
        'meal_entries': const [],
        'water_entries': const [],
        'weight_entries': const [],
      };
      repo = DiaryRepository(
        _clientWith((req) async {
          uris.add(req.url);
          return _respond(req, _rowsFor(req.url, rows));
        }),
      );
    });

    test('meal / water / weight sorgularının üçünde de deleted_at=is.null', () async {
      await repo.fetchDaily('u1', DateTime(2026, 8, 15));

      expect(uris, hasLength(3));
      for (final uri in uris) {
        expect(
          uri.queryParameters['deleted_at'],
          'is.null',
          reason: '${uri.path}: yumuşak silinmiş kayıt listeye girmemeli',
        );
      }
    });

    test('sunucu deleted_at filtresini uygulamazsa istemci son savunma yapar', () async {
      // Savunma-derinliği: süzgeç **sunucu** tarafında (RLS + `is.null`).
      // Yine de istemci katmanı `deleted_at` dolu satırı `DailyData`'ya
      // almıyor; aksi halde dashboard toplamları 9999 kcal'a çıkardı.
      // Bu, sorgu süzgeci bir gün kaldırılsa/RLS gevşese kullanıcının
      // beslenme kararını bozan "sessiz yanlış toplam"ı engelliyor.
      rows['meal_entries'] = [
        _mealRow('m1', 500, deletedAt: null),
        _mealRow('m2', 9999, deletedAt: '2026-08-15T12:00:00Z'),
      ];

      final data = await repo.fetchDaily('u1', DateTime(2026, 8, 15));

      expect(
        data.mealEntries.map((e) => e.id),
        ['m1'],
        reason: 'deleted_at dolu kayıt DailyData içine sızmamalı',
      );
      expect(data.totals.calories, 500.0,
          reason: 'silinen kayıt gün toplamına girmemeli');
      expect(data.totalWater, 0);
    });

    test('deleted_at süzgeci gönderildiği için sunucu silinmiş satır dönmemeli', () async {
      // Aynı senaryonun sunucu tarafı: doğru davranış `deleted_at=is.null`
      // filtresini uygulamak ve yalnızca canlı satırı döndürmektir.
      rows['meal_entries'] = [
        _mealRow('m1', 500, deletedAt: null),
      ];
      final data = await repo.fetchDaily('u1', DateTime(2026, 8, 15));
      final mealUri = _byTable(uris)['meal_entries']!;
      expect(mealUri.queryParameters['deleted_at'], 'is.null');
      expect(data.mealEntries, hasLength(1));
      expect(data.totals.calories, 500.0);
    });

    test('öğün ve su sorguları seçili günü filtreler', () async {
      await repo.fetchDaily('u1', DateTime(2026, 8, 15));
      final byTable = _byTable(uris);

      expect(byTable['meal_entries']!.queryParameters['user_id'], 'eq.u1');
      expect(byTable['meal_entries']!.queryParameters['entry_date'], 'eq.2026-08-15');
      expect(byTable['water_entries']!.queryParameters['entry_date'], 'eq.2026-08-15');
      // Kilo trendi tarih filtresiz (en son kayıt) — web parity.
      expect(byTable['weight_entries']!.queryParameters.containsKey('entry_date'),
          isFalse);
    });

    test('kilo sorgusu (created_at order yok) deleted_at + order + limit taşır', () async {
      await repo.fetchDaily('u1', DateTime(2026, 8, 15));
      final weight = _byTable(uris)['weight_entries']!;

      expect(weight.queryParameters['deleted_at'], 'is.null');
      expect(weight.queryParameters['order'], startsWith('entry_date.desc'));
      expect(weight.queryParameters['limit'], '1');
    });
  });

  group('analytics — silinen kayıtlar toplama giriyor mu', () {
    test('meal / water / weight sorguları deleted_at=is.null ile gider', () async {
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, const <Object>[]);
      });

      // Üç paralel sorgu; hepsi toplamlara/seriye girer, hepsinde süzgeç
      // zorunludur (analytics ekranı yanlış kalori toplamı gösterir).
      await AnalyticsRepository(client).fetch('u1', AnalyticsPeriod.week);

      final byTable = _byTable(uris);
      expect(byTable.keys,
          containsAll(<String>['meal_entries', 'water_entries', 'weight_entries']));
      for (final entry in byTable.entries) {
        expect(entry.value.queryParameters['deleted_at'], 'is.null',
            reason: '${entry.key} silinmiş kayıtları toplama katıyor olabilir');
      }
    });
  });

  group('deleteMealEntry / deleteWaterEntry — fiziksel silme değil', () {
    test('delete isteği PATCH + deleted_at UTC damgası + kapsam filtresi', () async {
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        return _respond(req, const <Object>[]);
      });
      await DiaryRepository(client).deleteMealEntry('u1', 'm1');

      final req = requests.single;
      expect(req.method, 'PATCH',
          reason: 'fiziksel DELETE yumuşak silmeyle çelişir; RLS DELETE '
              'politikası yazma yolundan bağımsız kalır');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body.keys, contains('deleted_at'));
      final deletedAt = DateTime.parse(body['deleted_at'] as String);
      expect(deletedAt.isUtc, isTrue,
          reason: 'timestamptz damgası UTC olmalı (+03:00 istemcide ~3 saat kayar)');
      expect(req.url.queryParameters['id'], 'eq.m1');
      expect(req.url.queryParameters['user_id'], 'eq.u1');
    });

    test('deleteWaterEntry de yumuşak siler (PATCH + deleted_at)', () async {
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        return _respond(req, const <Object>[]);
      });
      await DiaryRepository(client).deleteWaterEntry('u1', 'w1');

      final req = requests.single;
      expect(req.method, 'PATCH');
      expect((jsonDecode(req.body) as Map).keys, contains('deleted_at'));
      expect(req.url.queryParameters['user_id'], 'eq.u1');
    });
  });

  group('restoreMealEntry — geri alma gerçekten çalışıyor mu', () {
    test('deleted_at null yazılır, kapsam filtreli, satır doğrulanır', () async {
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        // `maybeSingle()` `Accept: application/vnd.pgrst.object+json` gönderir;
        // gerçek PostgREST bu durumda JSON **nesnesi** döner (dizi değil).
        return _respond(req, {'id': 'm1', 'deleted_at': null});
      });
      await DiaryRepository(client).restoreMealEntry('u1', 'm1');

      final req = requests.single;
      expect(req.method, 'PATCH');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['deleted_at'], isNull, reason: 'geri alma deleted_at\'ı temizler');
      expect(req.url.queryParameters['id'], 'eq.m1');
      expect(req.url.queryParameters['user_id'], 'eq.u1');
      // Doğrulama için satır geri okunur → sessiz başarısızlık olmaz.
      expect(req.url.queryParameters['select'], 'id,deleted_at');
    });

    test('satır yok (başka cihazda silinmiş) → StateError', () async {
      // `maybeSingle()` 0 satırda null döner. Eski sürüm bunu yutmuyordu:
      // kullanıcı "Geri Al" bastı, kayıt listede görünmedi, veri geri gelmedi
      // ve kullanıcı sessizce verisini kaybettiğini düşündü.
      final client = _clientWith((req) async => _respond(req, null));
      expect(
        () => DiaryRepository(client).restoreMealEntry('u1', 'yok'),
        throwsStateError,
      );
    });

    test('deleted_at hâlâ dolu dönerse StateError (yazma yutturulmuş)', () async {
      // RLS/trigger yazmayı yutmuşsa satır döner ama `deleted_at` dolu kalır;
      // "başarılı" demek yanlış olurdu.
      final client = _clientWith(
        (req) async => _respond(
          req,
          {'id': 'm1', 'deleted_at': '2026-08-15T11:00:00Z'},
        ),
      );
      expect(
        () => DiaryRepository(client).restoreMealEntry('u1', 'm1'),
        throwsStateError,
      );
    });
  });

  group('fetchDaily — bozuk satır tüm günü düşürmez', () {
    test('eksik zorunlu alanlı öğün atlanır, sağlam öğün kalır', () async {
      final client = _clientWith((req) async {
        if (req.url.path.endsWith('meal_entries')) {
          return _respond(req, [
            _mealRow('m1', 500),
            // `calculated_protein` eksik → `json_serializable` `as num`
            // zorlaması istisna fırlatır; tüm gün ekranı düşmemeli.
            {'id': 'm2', 'user_id': 'u1', 'meal_type': 'lunch', 'source': 'manual'},
          ]);
        }
        return _respond(req, const <Object>[]);
      });

      final data = await DiaryRepository(client).fetchDaily('u1', DateTime(2026, 8, 15));
      expect(data.mealEntries, hasLength(1));
      expect(data.mealEntries.single.id, 'm1');
      expect(data.totals.calories, 500.0);
    });
  });
}

/// Tablo adı → istek eşlemesi.
Map<String, Uri> _byTable(List<Uri> uris) => {
      for (final uri in uris) uri.path.split('/').last: uri,
    };

/// Sahte REST yanıtı: yolun sonuna göre tablo satırlarını seçer.
Object _rowsFor(Uri uri, Map<String, List<Map<String, dynamic>>> rows) {
  for (final entry in rows.entries) {
    if (uri.path.endsWith(entry.key)) return entry.value;
  }
  return const <Object>[];
}

Map<String, dynamic> _mealRow(
  String id,
  double kcal, {
  String? deletedAt,
}) =>
    {
      'id': id,
      'user_id': 'u1',
      'meal_type': 'lunch',
      'amount_g_ml': 100,
      'calculated_kcal': kcal,
      'calculated_protein': 30,
      'calculated_carbs': 40,
      'calculated_fat': 10,
      'entry_date': '2026-08-15',
      'source': 'manual',
      'created_at': '2026-08-15T10:00:00Z',
      'deleted_at': deletedAt,
    };
