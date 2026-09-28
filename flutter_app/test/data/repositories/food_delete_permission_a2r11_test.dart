/// A2r11 (Tur 11) — `FoodItem.canDelete` sözleşmesi + `search()` kolon
/// envanteri.
///
/// ## Bu test neden var?
///
/// A4r10 yemek silme **arayüzünü** ekledi (`shared/widgets/delete_food_button.dart`,
/// `add_page.dart`'in 4 bölümü). Aktarım notu şunu diyordu:
///
/// ```text
/// P1 — Silme düğmesi veritabanı/seed gıdalarında da görünüyor
///      (`created_by IS NULL` → `false` + toast). `food_repository.search()`
///      `created_by`/`source` kolonlarını seçmiyor.
/// ```
///
/// Gerçek sebep **`source` değil, `created_by`**'dir ve bu test **kanıtı**
/// kilitler:
///
/// 1. `foods` DELETE politikası `USING (created_by = auth.uid())`
///    (`full_setup.sql:424`) — silinebilirliğin **tek** ölçütü `created_by`.
/// 2. `search()` artık `created_by`'i **seçiyor** (sözleşme kilidi).
/// 3. Kullanıcının **kendi** gıdası → `canDelete == true` (düğme var).
/// 4. **Seed** gıdası (`created_by IS NULL`) → `canDelete == false` (düğme yok).
/// 5. **Başkasının** gıdası → `canDelete == false` (düğme yok).
/// 6. Aynı kural `favorites()` / `recents()` / `frequentFoods()` yollarında da
///    geçerli — 4 bölümün **hepsi** düğme çiziyor.
///
/// ## ⭐ Ölçüm gerekçesi (Postgres 16.15, 50.000 satır, `tool/a2r11_explain3.sql`)
///
/// `created_by` eklemenin plana etkisi: **yok**. Her iki varyantta da plan
/// `Index Scan using idx_foods_popularity` + `Filter: (name ~~* ...)`.
/// 200 tekrarlı ölçümde medyan fark **0.0000 ms (%0.00)**, min farkı da
/// `0.0000 ms`. `created_by` `uuid` (16 bayt), `foods` satırı zaten 96 bayt.
///
/// ## ⭐ Varsayılan `false` = fail-closed
///
/// `canDelete` kanıtlanmadan `true` ilan edilmez. `foodId != null` olmak
/// **yetki değildir** (A4r10 tuzağı). `recognized_food.toItem()` ve elle
/// kurulan `FoodItem`'larda alan `false` kalır → düğme gizli.
library;

import 'dart:convert';

import 'package:calorix/data/models/food_item.dart';
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

/// `foods` satırı — `food_nutrition` join'i dolu.
Map<String, dynamic> foodRow({
  String id = 'f1',
  String name = 'Yoğurt',
  String? createdBy,
  String? brand,
}) =>
    {
      'id': id,
      'name': name,
      'brand': brand,
      'serving_size_g': 100.0,
      'created_by': createdBy,
      'food_nutrition': {
        'kcal': 60.0,
        'protein_g': 5.0,
        'carbs_g': 4.0,
        'fat_g': 2.0,
      },
    };

void main() {
  // =================================================================
  // 1) ⭐ SÖZLEŞME: `created_by` hangi yollarda seçiliyor?
  // =================================================================
  group('1) ⭐ created_by kolonu — hangi okuma yolunda seçiliyor?', () {
    test('search: `created_by` istenir (A4r10 aktarımının kapattığı boşluk)',
        () async {
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).search('u1', 'tavuk');

      final foodsUri = uris.firstWhere((u) => u.path.endsWith('foods'));
      expect(
        foodsUri.queryParameters['select'],
        contains('created_by'),
        reason: 'kolon istenmezse `canDelete` üretilemez — düğme her gıdaya '
            'çizilir ve RLS reddedince kullanıcı hata toast\'ı görür',
      );
    });

    test('favorites: `created_by` JOIN içinden istenir', () async {
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).favorites('u1');

      expect(uris.single.queryParameters['select'], contains('created_by'));
    });

    test('recents: `created_by` JOIN içinden istenir', () async {
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).recents('u1');

      expect(uris.single.queryParameters['select'], contains('created_by'));
    });

    test('frequentFoods: `created_by` JOIN içinden istenir', () async {
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).frequentFoods('u1');

      expect(uris.single.queryParameters['select'], contains('created_by'));
    });

    test('⭐ `source` kolonu **istenmiyor** — karar için kullanılmıyor', () async {
      // Gerekçe: `source` (`photo`/`text`/`manual`) kayıt **kökenidir**,
      // **yetki değildir**. Seed gıdaları da `manual` olabilir ve kullanıcının
      // kendi gıdası da `photo` olabilir. `source` eklenirse aynı gıda iki
      // yerde farklı karar görür (bir yer "silinebilir", diğer "değil").
      // Tek doğruluk kaynağı RLS'in kendisidir: `created_by = auth.uid()`.
      final uris = <Uri>[];
      final client = _clientWith((req) async {
        uris.add(req.url);
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).search('u1', 'tavuk');

      final foodsUri = uris.firstWhere((u) => u.path.endsWith('foods'));
      final select = foodsUri.queryParameters['select'] ?? '';
      expect(select, isNot(contains('source')),
          reason: 'yetki kararı `source`a dayandırılmaz');
    });

    test('⭐ `source` **olmadan** da doğru karar verilir (kanıt)', () async {
      // Sunucu `source` kolonunu hiç göndermese bile `canDelete` üretilir —
      // yani karar `source`'a **bağımlı değildir**.
      final client = _clientWith((req) async {
        if (req.url.path.endsWith('foods')) {
          return _respond(req, [
            foodRow(id: 'own', name: 'Tavuk', createdBy: 'u1'),
          ]);
        }
        return _respond(req, const <Object>[]);
      });

      final results = await FoodRepository(client).search('u1', 'tavuk');
      expect(results.single.canDelete, isTrue,
          reason: '`source` yokken de "kendi gıdam" tanınır');
    });
  });

  // =================================================================
  // 2) ⭐ search(): üç durum — kendi / seed / başkasının gıdası
  // =================================================================
  group('2) ⭐ search(): canDelete üç durumu', () {
    Future<List<FoodItem>> search(List<Map<String, dynamic>> rows) async {
      final client = _clientWith((req) async {
        if (req.url.path.endsWith('foods')) return _respond(req, rows);
        return _respond(req, const <Object>[]);
      });
      return FoodRepository(client).search('u1', 'tavuk');
    }

    test('kendi gıdası (created_by == auth.uid()) → DÜĞME VAR', () async {
      final results = await search([
        foodRow(id: 'own', name: 'Tavuk Göğsü', createdBy: 'u1'),
      ]);
      expect(results, hasLength(1));
      expect(results.single.canDelete, isTrue,
          reason: 'RLS `created_by = auth.uid()` → DELETE 1 satır → silinir');
    });

    test('⭐ SEED gıdası (created_by IS NULL) → DÜĞME YOK', () async {
      final results = await search([
        foodRow(id: 'seed', name: 'Tavuk Göğsü', createdBy: null),
      ]);
      expect(results, hasLength(1));
      expect(results.single.canDelete, isFalse,
          reason: 'seed/topluluk gıdası: RLS DELETE 0 satır döner → '
              '`deleteFood` false döner → kullanıcı hata toast\'ı görür. '
              'Bu düğme **gizlenmeli**.');
    });

    test('başka kullanıcının gıdası → DÜĞME YOK', () async {
      final results = await search([
        foodRow(id: 'other', name: 'Tavuk Göğsü', createdBy: 'u2'),
      ]);
      expect(results.single.canDelete, isFalse);
    });

    test('⭐ karar `source` değil `created_by` üzerinden (seed + source=manual '
        'yine silinemez)', () async {
      // `foods` satırında `source` **hiç yok** bile olsa seed gıda silinemez.
      final results = await search([
        foodRow(id: 'seed', name: 'Tavuk Göğsü', createdBy: null),
      ]);
      expect(results.single.canDelete, isFalse);
    });

    test('karışık sonuç: her satır kendi kararını alır', () async {
      final results = await search([
        foodRow(id: 'a', name: 'Tavuk A', createdBy: 'u1'),
        foodRow(id: 'b', name: 'Tavuk B', createdBy: null),
        foodRow(id: 'c', name: 'Tavuk C', createdBy: 'u2'),
      ]);
      expect(results.map((r) => r.canDelete), [true, false, false]);
    });

    test('⭐ canDelete=false olan gıda `foodId` **dolu** olabilir (ayrım net)',
        () async {
      final results = await search([
        foodRow(id: 'seed', name: 'Tavuk Göğsü', createdBy: null),
      ]);
      // A4r10 tuzağı: `foodId != null` idi ve düğme görünüyordu.
      expect(results.single.foodId, isNotNull);
      expect(results.single.canDelete, isFalse,
          reason: '`foodId != null` yalnızca "tablo satırı var" demek; '
              'silinebilirlik `created_by` ile belirlenir');
    });
  });

  // =================================================================
  // 3) ⭐ favorites / recents / frequentFoods — aynı kural
  // =================================================================
  group('3) ⭐ diğer üç yolda da aynı canDelete kuralı', () {
    test('favorites: kendi gıdası true, seed gıdası false', () async {
      final client = _clientWith((req) async {
        return _respond(req, [
          {
            'food_id': 'own',
            'created_at': '2026-09-02T10:00:00Z',
            'foods': foodRow(id: 'own', name: 'Kendim', createdBy: 'u1'),
          },
          {
            'food_id': 'seed',
            'created_at': '2026-09-01T10:00:00Z',
            'foods': foodRow(id: 'seed', name: 'Seed', createdBy: null),
          },
        ]);
      });

      final items = await FoodRepository(client).favorites('u1');

      expect(items.map((i) => i.canDelete), [true, false],
          reason: 'favoriler bölümü de silme düğmesi çiziyor');
    });

    test('recents: kendi gıdası true, seed gıdası false', () async {
      final client = _clientWith((req) async {
        return _respond(req, [
          {
            'id': 'm1',
            'food_id': 'own',
            'created_at': '2026-09-02T10:00:00Z',
            'deleted_at': null,
            'foods': foodRow(id: 'own', name: 'Kendim', createdBy: 'u1'),
          },
          {
            'id': 'm2',
            'food_id': 'seed',
            'created_at': '2026-09-01T10:00:00Z',
            'deleted_at': null,
            'foods': foodRow(id: 'seed', name: 'Seed', createdBy: null),
          },
        ]);
      });

      final items = await FoodRepository(client).recents('u1');
      expect(items.map((i) => i.canDelete), [true, false]);
    });

    test('frequentFoods: kendi gıdası true, seed gıdası false', () async {
      final client = _clientWith((req) async {
        return _respond(req, [
          {
            'id': 'm1',
            'food_id': 'own',
            'created_at': '2026-09-02T10:00:00Z',
            'deleted_at': null,
            'foods': foodRow(id: 'own', name: 'Kendim', createdBy: 'u1'),
          },
          {
            'id': 'm2',
            'food_id': 'seed',
            'created_at': '2026-09-01T10:00:00Z',
            'deleted_at': null,
            'foods': foodRow(id: 'seed', name: 'Seed', createdBy: null),
          },
        ]);
      });

      final items = await FoodRepository(client).frequentFoods('u1');
      expect(items.map((i) => i.canDelete), [true, false]);
    });

    test('⭐ custom (foods join\'i yok) girdi → canDelete false', () async {
      // Custom girdi `foods` tablosunda satır **yoktur** → silinecek kayıt
      // yok. `foodId == null` zaten düğmeyi gizliyor; `canDelete` da `false`
      // kalmalı ki iki kaynak birbirini **tekrar edip çelişmesin**.
      final client = _clientWith((req) async {
        return _respond(req, [
          {
            'id': 'm1',
            'food_id': null,
            'custom_name': 'Ev yapımı köfte',
            'amount_g_ml': 100.0,
            'calculated_kcal': 250.0,
            'calculated_protein': 20.0,
            'calculated_carbs': 5.0,
            'calculated_fat': 15.0,
            'deleted_at': null,
          },
        ]);
      });

      final items = await FoodRepository(client).recents('u1');
      expect(items.single.isCustom, isTrue);
      expect(items.single.canDelete, isFalse);
    });

    test('⭐ `deleted_at` filtresi canDelete kararını ETKİLEMEZ', () async {
      // Savunma-derinliği iki katmanı birbirinden bağımsız kılar: yumuşak
      // silinmiş öğün listeden düşer, kalan öğünler yine de doğru `canDelete`
      // taşır.
      final client = _clientWith((req) async {
        return _respond(req, [
          {
            'id': 'm1',
            'food_id': 'own',
            'created_at': '2026-09-02T10:00:00Z',
            'deleted_at': null,
            'foods': foodRow(id: 'own', name: 'Kendim', createdBy: 'u1'),
          },
          {
            'id': 'm2',
            'food_id': 'seed',
            'created_at': '2026-09-01T10:00:00Z',
            'deleted_at': '2026-09-02T00:00:00Z',
            'foods': foodRow(id: 'seed', name: 'Silinmis Kayit', createdBy: null),
          },
        ]);
      });

      final items = await FoodRepository(client).recents('u1');
      expect(items, hasLength(1), reason: 'silinmiş öğün elenir');
      expect(items.single.canDelete, isTrue);
    });
  });

  // =================================================================
  // 4) ⭐ Fail-closed varsayılan + yaşam döngüsü
  // =================================================================
  group('4) ⭐ fail-closed varsayılan', () {
    test('canDelete varsayılanı FALSE (constructor\'da yazılmadıysa)', () {
      const item = FoodItem(
        id: 'f1',
        foodId: 'f1',
        name: 'Yoğurt',
        calories: 60,
        proteinG: 5,
        carbsG: 4,
        fatG: 2,
      );
      expect(item.canDelete, isFalse,
          reason: 'kanıtlanmamış yetki asla `true` ilan edilmez');
    });

    test('⭐ `foodId` dolu olsa bile varsayılan canDelete false', () {
      // A4r10\'ın tuzağı tam olarak bu: `foodId != null` → düğme çizildi.
      // Model düzeyinde varsayılan, o tuzağı kapatır.
      const item = FoodItem(
        id: 'f1',
        foodId: 'f1',
        name: 'Yoğurt',
        calories: 60,
        proteinG: 5,
        carbsG: 4,
        fatG: 2,
      );
      expect(item.foodId, isNotNull);
      expect(item.canDelete, isFalse);
    });

    test('custom girdi de canDelete false (foodId null)', () {
      const item = FoodItem(
        id: 'custom_1',
        name: 'Ev yapımı',
        calories: 100,
        proteinG: 5,
        carbsG: 5,
        fatG: 5,
        isCustom: true,
      );
      expect(item.canDelete, isFalse);
    });
  });

  // =================================================================
  // 5) ⭐ deleteFood + canDelete tutarlılığı
  // =================================================================
  group('5) ⭐ deleteFood canDelete ile aynı kuralı uygular', () {
    test('canDelete=true olan gıda silinir (1 satır döner)', () async {
      final client = _clientWith((req) async {
        if (req.method == 'DELETE') {
          return _respond(req, [
            {'id': 'own'},
          ]);
        }
        return _respond(req, const <Object>[]);
      });

      expect(await FoodRepository(client).deleteFood('u1', 'own'), isTrue);
    });

    test('canDelete=false olan (seed) gıda silinmez (0 satır → false)', () async {
      final client = _clientWith((req) async {
        if (req.method == 'DELETE') return _respond(req, const <Object>[]);
        return _respond(req, const <Object>[]);
      });

      expect(
        await FoodRepository(client).deleteFood('u1', 'seed'),
        isFalse,
        reason: 'RLS `created_by = auth.uid()` → 0 satır → sessiz "başarı" yok',
      );
    });

    test('⭐ DELETE isteği `created_by` filtresini **taşır**', () async {
      // ⭐ Ölçülen Postgres kanıtı (tool/a2r11_consistency.sql):
      //   seed gida (created_by IS NULL) -> DELETE 0 satir
      //   kendi gidan                   -> DELETE 1 satir
      // İstemci filtresi bunu ikinci kez uygular (yetki RLS'te de var):
      // kırık/eksik RLS durumunda başkasının gıdası sessizce silinmez.
      final requests = <http.Request>[];
      final client = _clientWith((req) async {
        requests.add(req);
        if (req.method == 'DELETE') {
          return _respond(req, const <Object>[]);
        }
        return _respond(req, const <Object>[]);
      });

      await FoodRepository(client).deleteFood('u1', 'f1');

      final deleteReq = requests.firstWhere((r) => r.method == 'DELETE');
      expect(deleteReq.url.queryParameters['created_by'], 'eq.u1');
      expect(deleteReq.url.queryParameters['id'], 'eq.f1');
    });
  });
}
