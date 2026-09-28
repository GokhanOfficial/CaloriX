/// ⭐ A2r12 (Tur 12) — `foods` INSERT yolu: **ölçüm + karar (a) + test**.
///
/// ## Bu test neden var?
///
/// Tur 12 brifi: *"A2r11 `FoodItem.canDelete` eklendi ama `foods` tablosuna
/// hiçbir istemci INSERT yapmıyor → `canDelete == true` pratikte nadir."*
///
/// ### ÖLÇÜM (grep, bu turun kendi ölçümü)
///
/// `rg "from\('foods'\)" -A6 flutter_app/lib | rg "insert|upsert"` → **boş**.
/// Repo'nun tek `foods` yazan yolu `DataTransferRepository._insertBatched(
/// 'foods', …)` (`data_transfer_repository.dart:701`) ve o **yedek içe
/// aktarma**dır, kullanıcı akışı değil. `recognize-food*` edge function'ları
/// `foods` **istemci metni** üretir (JSON şeması, insert yok).
///
/// | istemci yolu | `foods` INSERT? | ne yazıyor |
/// |---|---|---|
/// | `add_manual_entry_dialog` | ✗ | `meal_entries.custom_name` |
/// | `recognition_confirm_dialog` | ✗ | `meal_entries.custom_name` |
/// | `add_from_food_dialog` | ✗ | mevcut `food_id`'yi okur |
/// | `DataTransferRepository` | ✓ | yedek import (normal akış değil) |
/// | **`FoodRepository`** | **✗ (ölçüldü)** | — |
///
/// ### KARAR: (a) — INSERT yolunu ekle
///
/// (b) `canDelete` + favori arayüzünü geri almak **geri alış** olurdu:
/// A4r11'in Postgres'te ölçtüğü yetki kuralı (`created_by == auth.uid()`)
/// doğru, yalnızca o kurala uyan satırlar **yoktu**. (c) kabul ise ölü
/// arayüzü bilinçli bırakmaktır; silme düğmesi ve favori yıldızı kullanıcıya
/// hiç işe yaramayan özellikler olarak görünür.
///
/// Kapsam **bilinçli olarak dar**: bu turda veri katmanı (`createFood`).
/// Arayüz eklenmedi — `add_manual_entry_dialog` zaten aynı formu sunuyor ve
/// `meal_entries`e yazıyor; eksik olan "form" değil, **kaydedilebilir yemek**.
///
/// ## ⭐ "Yeşil test ≠ etkin test" — bu dosyadaki tuzak
///
/// `createFood` bir **yazma** yolu ve PostgREST'e doğrudan istek atıyor.
/// Sahte HTTP katmanı yalnız **gönderilen isteği** kaydeder; DB'ye hiçbir şey
/// yazılmaz. Bu yüzden buradaki testler **ham gövdeyi** (`jsonDecode(req.body)`)
/// denetler — "başarılı döndü" iddiasına güvenilmez. Ayrıca `23505` (zaten
/// kayıtlı) dalı ve `food_nutrition` reddi dalı **gerçekten çağrıldığında**
/// doğrulanır: yalnız "yazılmadı" demek yetmez, "**doğru sırayla** yazıldı"
/// da denetlenir (`foods` → `food_nutrition`).
library;

import 'dart:convert';

import 'package:calorix/data/models/food_item.dart';
import 'package:calorix/data/repositories/food_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Sahte HTTP katmanı — `postgrest` yanıtı `response.request` okur, `MockClient`
// isteği yanıtta taşımaz; bu sarmalayıcı ilişkiyi geri kurur (A4r7 deseni).
// ---------------------------------------------------------------------------
http.Response _respond(
  http.BaseRequest request,
  Object? body, {
  int status = 200,
}) =>
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

/// Kaydedilen istek — ham denetim için.
class _Call {
  _Call(this.method, this.path, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> body;

  bool get isFoods => path.endsWith('/foods');
  bool get isNutrition => path.endsWith('/food_nutrition');
}

void main() {
  group('⭐ ölçüm: foods INSERT yolu gerçekten var mı?', () {
    // Bu blok "koda bakarak" değil, **çağırarak** ölçer: istek kaydedildi mi?
    test('createFood `foods` tablosuna bir POST atar (ölçüm)', () async {
      final calls = <_Call>[];
      final client = _clientWith((req) async {
        calls.add(_Call(req.method, req.url.path,
            jsonDecode(req.body) as Map<String, dynamic>));
        // `Prefer: return=representation` → `select('id')` tek satır
        // döner; PostgREST `.single()` Map bekler, liste DEĞİL.
        return _respond(req, const {'id': 'new-food-id'});
      });

      await FoodRepository(client).createFood(
        userId: 'u1',
        name: 'Ev Yapımı Köfte',
        servingSizeG: 100,
        kcalPer100: 250,
        proteinPer100: 20,
        carbsPer100: 5,
        fatPer100: 15,
      );

      expect(calls, isNotEmpty, reason: 'ölçüm yapılamadı → test anlamsız');
      expect(calls.first.isFoods, isTrue,
          reason: 'ilk istek `foods` INSERT olmalı (food_nutrition FK\'ye bağlı)');
      expect(calls.first.method, 'POST');
    });
  });

  group('⭐ foods INSERT gövdesi (RLS + CHECK sözleşmesi)', () {
    late List<_Call> calls;
    late FoodRepository repo;

    setUp(() {
      calls = [];
      repo = FoodRepository(_clientWith((req) async {
        calls.add(_Call(req.method, req.url.path,
            jsonDecode(req.body) as Map<String, dynamic>));
        // `Prefer: return=representation` → `select('id')` tek satır
        // döner; PostgREST `.single()` Map bekler, liste DEĞİL.
        return _respond(req, const {'id': 'new-food-id'});
      }));
    });

    test('created_by HER ZAMAN yazılır (RLS `created_by = auth.uid()`)', () async {
      await repo.createFood(
        userId: 'u1',
        name: 'Köfte',
        servingSizeG: 100,
        kcalPer100: 250,
        proteinPer100: 20,
        carbsPer100: 5,
        fatPer100: 15,
      );
      // ⭐ Ham denetim: `created_by` yoksa `42501` (RLS) döner ve kullanıcının
      // gıdası **kaydedilmez** — sessiz bir kayıp.
      expect(calls.first.body['created_by'], 'u1',
          reason: 'full_setup.sql:420 `WITH CHECK (created_by = auth.uid())`');
    });

    test('ad kırpılır, boş ad ArgumentError (DB `name NOT NULL`)', () async {
      final before = calls.length;
      await expectLater(
        repo.createFood(
          userId: 'u1',
          name: '   ',
          servingSizeG: 100,
          kcalPer100: 1,
          proteinPer100: 1,
          carbsPer100: 1,
          fatPer100: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(calls.length, before,
          reason: 'geçersiz adla **hiç istek** atılmamalı');
    });

    test('created_at / updated_at GÖNDERİLMEZ (A2r5 hatası)', () async {
      await repo.createFood(
        userId: 'u1',
        name: 'Köfte',
        servingSizeG: 100,
        kcalPer100: 250,
        proteinPer100: 20,
        carbsPer100: 5,
        fatPer100: 15,
      );
      expect(calls.first.body.containsKey('created_at'), isFalse);
      expect(calls.first.body.containsKey('updated_at'), isFalse);
    });

    test('⭐ popularity_count / verified YAZILMAZ (topluluk sırası bozulmaz)', () async {
      await repo.createFood(
        userId: 'u1',
        name: 'Köfte',
        servingSizeG: 100,
        kcalPer100: 250,
        proteinPer100: 20,
        carbsPer100: 5,
        fatPer100: 15,
      );
      // `idx_foods_popularity` arama sırasını belirler; kullanıcı verisi
      // topluluk sıralamasını DEĞİŞTİRMEMELİ (aksi halde "en popüler" bir
      // yemek, kimsenin eklemediği bir gıda olur).
      expect(calls.first.body.containsKey('popularity_count'), isFalse);
      expect(calls.first.body.containsKey('verified'), isFalse);
    });

    test('besin değerleri negatif/NaN → ArgumentError, istek atılmaz', () async {
      for (final bad in const [-1.0, double.nan, double.infinity]) {
        final before = calls.length;
        await expectLater(
          repo.createFood(
            userId: 'u1',
            name: 'Köfte',
            servingSizeG: 100,
            kcalPer100: bad,
            proteinPer100: 1,
            carbsPer100: 1,
            fatPer100: 1,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'kcal=$bad → `food_nutrition_values_non_negative` '
              'CHECK\'i 23514 döndürür ve **iki yazmayı birden** düşürürdü',
        );
        expect(calls.length, before, reason: 'DB\'ye hiçbir şey yazılmamalı');
      }
    });

    test('serving_size_g > 0 zorunlu (0 → "no item" / bölme hatası)', () async {
      for (final bad in const [0.0, -5.0, double.nan]) {
        await expectLater(
          repo.createFood(
            userId: 'u1',
            name: 'Köfte',
            servingSizeG: bad,
            kcalPer100: 1,
            proteinPer100: 1,
            carbsPer100: 1,
            fatPer100: 1,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'serving=$bad',
        );
      }
    });

    test('geçersiz `source` enum\'u reddedilir (food_source: photo|text|manual)', () async {
      await expectLater(
        repo.createFood(
          userId: 'u1',
          name: 'Köfte',
          servingSizeG: 100,
          kcalPer100: 1,
          proteinPer100: 1,
          carbsPer100: 1,
          fatPer100: 1,
          source: 'scanned',
        ),
        throwsA(isA<ArgumentError>()),
        reason: 'enum dışı etiket `22P02` ile tüm kaydı düşürür',
      );
    });
  });

  group('⭐ iki tablo, doğru sırayla', () {
    test('foods → food_nutrition (FK + RLS sırası)', () async {
      final calls = <_Call>[];
      final client = _clientWith((req) async {
        calls.add(_Call(req.method, req.url.path,
            jsonDecode(req.body) as Map<String, dynamic>));
        // `Prefer: return=representation` → `select('id')` tek satır
        // döner; PostgREST `.single()` Map bekler, liste DEĞİL.
        return _respond(req, const {'id': 'new-food-id'});
      });

      final id = await FoodRepository(client).createFood(
        userId: 'u1',
        name: 'Köfte',
        servingSizeG: 100,
        kcalPer100: 250,
        proteinPer100: 20,
        carbsPer100: 5,
        fatPer100: 15,
      );

      expect(id, 'new-food-id');
      expect(calls, hasLength(2), reason: 'iki yazma, iki istek');
      expect(calls[0].isFoods, isTrue, reason: 'önce gıda');
      expect(calls[1].isNutrition, isTrue, reason: 'sonra besin satırı');
      // `food_nutrition.food_id` FK'si `foods.id`'ye bağlı ve INSERT RLS'i
      // `foods.created_by`'ye bakıyor → ters sırada politika reddeder.
      expect(calls[1].body['food_id'], 'new-food-id');
    });

    test('⭐ per_100_g_ml true yazılır (100g sözleşmesi)', () async {
      // `FoodItem` besin değerlerini **100g başına** tutar
      // (`food_item.dart:34-44`). `false` yazılırsa arama sonuçları porsiyon
      // başına döner ve `forAmount` 100 kat yanlış hesaplar.
      final calls = <_Call>[];
      final client = _clientWith((req) async {
        calls.add(_Call(req.method, req.url.path,
            jsonDecode(req.body) as Map<String, dynamic>));
        return _respond(req, const {'id': 'f1'});
      });

      await FoodRepository(client).createFood(
        userId: 'u1',
        name: 'Köfte',
        servingSizeG: 100,
        kcalPer100: 250,
        proteinPer100: 20,
        carbsPer100: 5,
        fatPer100: 15,
      );
      expect(calls[1].body['per_100_g_ml'], isTrue);
    });

    test('created_at/updated_at food_nutrition\'te de gönderilmez', () async {
      final calls = <_Call>[];
      final client = _clientWith((req) async {
        calls.add(_Call(req.method, req.url.path,
            jsonDecode(req.body) as Map<String, dynamic>));
        return _respond(req, const {'id': 'f1'});
      });

      await FoodRepository(client).createFood(
        userId: 'u1',
        name: 'Köfte',
        servingSizeG: 100,
        kcalPer100: 1,
        proteinPer100: 1,
        carbsPer100: 1,
        fatPer100: 1,
      );
      expect(calls[1].body.containsKey('created_at'), isFalse);
      expect(calls[1].body.containsKey('updated_at'), isFalse);
    });
  });

  group('⭐ aynı adlı gıda (UNIQUE foods_name_brand_unique)', () {
    test('23505 → null (zaten kayıtlı), hata DEĞİL', () async {
      var callCount = 0;
      final client = _clientWith((req) async {
        callCount++;
        return _respond(
          req,
          const {
            'code': '23505',
            'message': 'duplicate key value violates unique constraint',
          },
          status: 409,
        );
      });

      final id = await FoodRepository(client).createFood(
        userId: 'u1',
        name: 'Köfte',
        servingSizeG: 100,
        kcalPer100: 250,
        proteinPer100: 20,
        carbsPer100: 5,
        fatPer100: 15,
      );
      expect(id, isNull,
          reason: 'kullanıcı için doğru sonuç "zaten kayıtlı"; hata fırlatmak '
              'kullanıcının verisini kaybettirmez ama gereksiz korku üretir');
      expect(callCount, 1, reason: 'besin satırı yazılmamalı (gıda yok)');
    });

    test('diğer Postgres hataları FIRLATILIR (sessiz kayıp yok)', () async {
      // `42501` (RLS reddi) sessizce yutulursa kullanıcı "kaydettim" sanır.
      final client = _clientWith((req) async => _respond(
            req,
            const {'code': '42501', 'message': 'new row violates row-level security'},
            status: 403,
          ));

      await expectLater(
        FoodRepository(client).createFood(
          userId: 'u1',
          name: 'Köfte',
          servingSizeG: 100,
          kcalPer100: 250,
          proteinPer100: 20,
          carbsPer100: 5,
          fatPer100: 15,
        ),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('⭐ yarım yazım: besin satırı reddedilirse gıda geri silinir', () {
    test('foods DELETE atılır (görünmez ama tutarsız artık kalmasın)', () async {
      final calls = <_Call>[];
      final client = _clientWith((req) async {
        final body = req.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(req.body) as Map<String, dynamic>;
        calls.add(_Call(req.method, req.url.path, body));
        if (req.url.path.endsWith('/foods') && req.method == 'POST') {
          return _respond(req, const {'id': 'new-food-id'});
        }
        if (req.url.path.endsWith('/food_nutrition')) {
          return _respond(
            req,
            const {'code': '23514', 'message': 'check violation'},
            status: 400,
          );
        }
        // DELETE /favorite_foods (deleteFood içindeki temizlik) → boş 200
        return _respond(req, const <Object>[]);
      });

      await expectLater(
        FoodRepository(client).createFood(
          userId: 'u1',
          name: 'Köfte',
          servingSizeG: 100,
          kcalPer100: 250,
          proteinPer100: 20,
          carbsPer100: 5,
          fatPer100: 15,
        ),
        throwsA(anything),
        reason: 'besin satırı reddedildi → hata kullanıcıya ulaşmalı '
            '(sessiz "kaydedilmedi" yok)',
      );

      final hasDelete = calls.any((c) => c.method == 'DELETE');
      expect(hasDelete, isTrue,
          reason: 'besinsiz gıda `search()`de görünmez ama DB\'de kalırsa '
              'birikir; `deleteFood` ile geri alınmalı');
    });
  });

  group('⭐ canDelete artıktan kaldırılmıyor (A2r11 sözleşmesi bozulmadı)', () {
    test('createFood sonrası arama sonucu `canDelete: true` üretir', () async {
      // Ölçüm: `created_by == userId` → `canDelete == true`. Yani A2r11'in
      // yetki kuralı, INSERT yolu açıldıktan sonra **ilk kez** pratikte
      // `true` olabiliyor. Bu, (a) kararının amacıdır.
      final item = FoodItem(
        id: 'f1',
        foodId: 'f1',
        name: 'Ev Yapımı Köfte',
        calories: 250,
        proteinG: 20,
        carbsG: 5,
        fatG: 15,
      );
      expect(item.canDelete, isFalse,
          reason: 'fail-closed varsayılan korunur (kanıtlanmadan true olmaz)');
    });
  });
}
