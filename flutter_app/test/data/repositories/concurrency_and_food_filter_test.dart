import 'dart:convert';

import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/data/repositories/food_repository.dart';
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

Map<String, dynamic> mealRow({
  String id = 'm1',
  double kcal = 500,
  String? updatedAt = '2026-08-15T10:00:00.000Z',
  String? deletedAt,
}) =>
    {
      'id': id,
      'user_id': 'u1',
      'meal_type': 'lunch',
      'custom_name': 'Tavuk',
      'amount_g_ml': 100,
      'calculated_kcal': kcal,
      'calculated_protein': 30,
      'calculated_carbs': 40,
      'calculated_fat': 10,
      'entry_date': '2026-08-15',
      'source': 'manual',
      'created_at': '2026-08-15T09:00:00Z',
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
    };

void main() {
  // =================================================================
  // 1) Eşzamanlı düzenleme — iyimser kilit
  // =================================================================
  group('updateMealEntry — eşzamanlı düzenleme (kayıp güncelleme)', () {
    test('damga verilince UPDATE `updated_at` filtresi taşır', () async {
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        return _respond(req, [mealRow(kcal: 600)]);
      });

      await DiaryRepository(client).updateMealEntry(
        'u1',
        'm1',
        {'custom_name': 'Tavuk'},
        expectedUpdatedAt: '2026-08-15T10:00:00.000Z',
      );

      expect(requests.single.method, 'PATCH');
      expect(requests.single.url.queryParameters['updated_at'],
          'eq.2026-08-15T10:00:00.000Z',
          reason: 'iyimser kilit: yalnızca aynı sürüm yazılır');
      expect(requests.single.url.queryParameters['id'], 'eq.m1');
      expect(requests.single.url.queryParameters['user_id'], 'eq.u1');
    });

    test('damga verilmezse filtre yok (son yazan kazanır — geriye uyum)',
        () async {
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        return _respond(req, [mealRow()]);
      });

      await DiaryRepository(client).updateMealEntry('u1', 'm1', {'note': 'x'});

      expect(requests.single.url.queryParameters.containsKey('updated_at'),
          isFalse);
    });

    test('çakışma: 0 satır + kayıt hâlâ canlı → MealEntryConflictError', () async {
      // Telefonda kaydedildi (damga değişti), tablette eski damga ile
      // yazılmaya çalışılıyor → 0 satır.
      final client = _clientWith((req) async {
        if (req.method == 'PATCH') return _respond(req, const <Object>[]);
        // Ayırt etme okuması.
        return _respond(req, {
          'updated_at': '2026-08-15T11:30:00.000Z',
          'deleted_at': null,
        });
      });

      await expectLater(
        DiaryRepository(client).updateMealEntry(
          'u1',
          'm1',
          {'custom_name': 'Pilav'},
          expectedUpdatedAt: '2026-08-15T10:00:00.000Z',
        ),
        throwsA(isA<MealEntryConflictError>()
            .having((e) => e.entryId, 'entryId', 'm1')
            .having((e) => e.expectedUpdatedAt, 'expected',
                '2026-08-15T10:00:00.000Z')
            .having((e) => e.actualUpdatedAt, 'actual',
                '2026-08-15T11:30:00.000Z')),
      );
    });

    test('çakışma: kayıt başka cihazdan silinmişse StateError (çakışma değil)',
        () async {
      final client = _clientWith((req) async {
        if (req.method == 'PATCH') return _respond(req, const <Object>[]);
        return _respond(req, {
          'updated_at': '2026-08-15T11:30:00.000Z',
          'deleted_at': '2026-08-15T12:00:00.000Z',
        });
      });

      await expectLater(
        DiaryRepository(client).updateMealEntry(
          'u1',
          'm1',
          {'note': 'x'},
          expectedUpdatedAt: '2026-08-15T10:00:00.000Z',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('çakışma: kayıt tamamen yoksa StateError', () async {
      final client = _clientWith((req) async {
        if (req.method == 'PATCH') return _respond(req, const <Object>[]);
        return _respond(req, null);
      });

      await expectLater(
        DiaryRepository(client).updateMealEntry(
          'u1',
          'yok',
          {'note': 'x'},
          expectedUpdatedAt: '2026-08-15T10:00:00.000Z',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('damga verilmeden 0 satır → StateError (bulunamadı)', () async {
      final client =
          _clientWith((req) async => _respond(req, const <Object>[]));
      await expectLater(
        DiaryRepository(client).updateMealEntry('u1', 'yok', {'note': 'x'}),
        throwsA(isA<StateError>()),
      );
    });

    test('başarılı yazma: yalnız bir PATCH, tek istek', () async {
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        return _respond(req, [mealRow(kcal: 550)]);
      });

      final updated = await DiaryRepository(client).updateMealEntry(
        'u1',
        'm1',
        {'amount_g_ml': 120.0, 'calculated_kcal': 550.0},
        expectedUpdatedAt: '2026-08-15T10:00:00.000Z',
      );

      expect(requests, hasLength(1), reason: 'başarılı yazmada ek okuma yok');
      expect(updated.calculatedKcal, 550.0);
      expect(updated.id, 'm1');
    });

    test('yazma sınırları çakışma kontrolünden ÖNCE uygulanır', () async {
      // 0 miktar yazılamaz; çakışma kontrolüne hiç gidilmez (gereksiz ağ).
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        return _respond(req, [mealRow()]);
      });

      await expectLater(
        DiaryRepository(client).updateMealEntry(
          'u1',
          'm1',
          {'amount_g_ml': 0.0},
          expectedUpdatedAt: '2026-08-15T10:00:00.000Z',
        ),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
    });
  });

  // =================================================================
  // 2) food_repository — silinmiş kayıt istemci süzgeci
  // =================================================================
  group('food_repository — yumuşak silinmiş kayıtlar listeye sızmaz', () {
    test('search: deleted_at kolonu istenir + sunucu süzgeci gider', () async {
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).search('u1', 'tavuk');

      final mealUri = uris.firstWhere((u) => u.path.endsWith('meal_entries'));
      expect(mealUri.queryParameters['deleted_at'], 'is.null');
      expect(mealUri.queryParameters['select'], contains('deleted_at'),
          reason: 'istemci elemesi ancak kolon geldiyse mümkün');
    });

    test('search: sunucu süzgeci uygulamazsa silinmiş öğün elenir', () async {
      // RLS/süzgeç bir gün gevşerse veya bozuk bir edge function filtresiz
      // veri döndürürse, silinmiş öğün "tekrar eklenebilir yemek" olarak
      // görünmemeli.
      final client = _clientWith((req) async {
        if (req.url.path.endsWith('foods')) {
          return _respond(req, const <Object>[]);
        }
        return _respond(req, [
          {
            'id': 'm1',
            'custom_name': 'Tavuk',
            'amount_g_ml': 100,
            'calculated_kcal': 500,
            'calculated_protein': 30,
            'calculated_carbs': 40,
            'calculated_fat': 10,
            'food_id': null,
            'deleted_at': null,
          },
          {
            'id': 'm2',
            'custom_name': 'Pilav',
            'amount_g_ml': 100,
            'calculated_kcal': 300,
            'calculated_protein': 6,
            'calculated_carbs': 60,
            'calculated_fat': 2,
            'food_id': null,
            'deleted_at': '2026-08-15T12:00:00Z',
          },
        ]);
      });

      final results = await FoodRepository(client).search('u1', 'av');
      expect(results.map((r) => r.name), ['Tavuk'],
          reason: 'silinmiş öğün arama sonucunda görünmemeli');
    });

    test('frequentFoods: silinmiş öğün sayıma girmez (deleted_at istenir)',
        () async {
      // A4r7: `favorites` artık `favorite_foods` **tablosundan** okuyor
      // (kullanıcının seçtiği favoriler). Türetilmiş "en çok yenilenler"
      // listesi `frequentFoods` adıyla korundu ve bu sözleşme **ona** aittir.
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, [
          {
            'id': 'm1',
            'custom_name': 'Tavuk',
            'amount_g_ml': 100,
            'calculated_kcal': 500,
            'calculated_protein': 30,
            'calculated_carbs': 40,
            'calculated_fat': 10,
            'food_id': null,
            'deleted_at': null,
          },
          {
            'id': 'm2',
            'custom_name': 'Tavuk',
            'amount_g_ml': 100,
            'calculated_kcal': 500,
            'calculated_protein': 30,
            'calculated_carbs': 40,
            'calculated_fat': 10,
            'food_id': null,
            'deleted_at': '2026-08-15T12:00:00Z',
          },
        ]);
      });

      final items = await FoodRepository(client).frequentFoods('u1');
      expect(items, hasLength(1));
      expect(items.single.useCount, 1,
          reason: 'silinmiş ikinci kayıt sayıma katılmamalı');

      final mealUri = uris.firstWhere((u) => u.path.endsWith('meal_entries'));
      expect(mealUri.queryParameters['select'], contains('deleted_at'));
      expect(mealUri.queryParameters['deleted_at'], 'is.null');
    });

    test('recents: silinmiş öğün son-yenilenlerde görünmez', () async {
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, [
          {
            'id': 'm1',
            'custom_name': 'Pilav',
            'amount_g_ml': 100,
            'calculated_kcal': 300,
            'calculated_protein': 6,
            'calculated_carbs': 60,
            'calculated_fat': 2,
            'food_id': null,
            'created_at': '2026-08-15T12:00:00Z',
            'deleted_at': '2026-08-15T12:30:00Z',
          },
        ]);
      });

      final items = await FoodRepository(client).recents('u1');
      expect(items, isEmpty);
      final mealUri = uris.firstWhere((u) => u.path.endsWith('meal_entries'));
      expect(mealUri.queryParameters['select'], contains('deleted_at'));
    });

    test('deleted_at eksik satır silinmemiş sayılır (seri boşalmaz)', () async {
      // Kolon eski şemada yoksa veya özel sorguda istenmemişse tüm listeyi
      // boşaltmak daha kötü bir hatadır (analytics ile aynı kural).
      final client = _clientWith((req) async {
        if (req.url.path.endsWith('foods')) {
          return _respond(req, const <Object>[]);
        }
        return _respond(req, [
          {
            'id': 'm1',
            'custom_name': 'Çay',
            'amount_g_ml': 100,
            'calculated_kcal': 2,
            'calculated_protein': 0,
            'calculated_carbs': 0,
            'calculated_fat': 0,
            'food_id': null,
          },
        ]);
      });

      final results = await FoodRepository(client).search('u1', 'çay');
      expect(results, hasLength(1));
    });
  });
}
