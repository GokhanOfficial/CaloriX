import 'dart:convert';

import 'package:calorix/data/repositories/diary_repository.dart';
import 'package:calorix/data/repositories/food_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A2r9 — yeni yazma yollarının veri sözleşmesi denetimi (Görev 5).
///
/// A4r7'in commit'i (`favorite_foods` tablosuna geçiş, "ürün kararı 1-A")
/// `lib/data/repositories/food_repository.dart` içine yeni yollar ekledi:
/// `addFavorite` / `removeFavorite` / `isFavorite` / `favoriteIds` /
/// `favorites` / `deleteFood`. Bu dosya o yolların:
///
///  1. **Sözleşmesini** kilitler (hangi tablo, hangi filtre, hangi kolon),
///  2. **Yumuşak silme süzgeci** açısından yeni yollarla eski yolları
///     karşılaştırır (A2r3'ün eklediği `deleted_at IS NULL` + istemci elemesi
///     deseni yeni yollarda unutulmuş olabilirdi),
///  3. `select()` listelerinin istemci elemesi için gereken **kolonu
///     getirdiğini** doğrular (`deleted_at` kastedir).
void main() {
  // =================================================================
  // 1) ⭐ Yumuşak silme: `deleted_at` süzgeci HANGİ yollarda var?
  // =================================================================
  group('1) deleted_at süzgeci — yol envanteri', () {
    /// `meal_entries` üzerindeki yumuşak silme kullanan **okuma** yolları.
    ///
    /// `DiaryRepository.fetchDaily` + `FoodRepository.search/frequentFoods/
    /// recents` — hepsi `meal_entries`'ten okuyor. A2r3 bu deseni 4 yola
    /// ekledi; A4r7 favorileri tabloya taşırken `favorites()` yeni bir yol
    /// açtı ve bu yol `meal_entries`'e **hiç dokunmuyor** (doğru).
    test('⭐ `meal_entries` okuyan HER yol sunucu süzgeci gönderiyor', () async {
      // A2r3 bu deseni 4 yola ekledi; A4r7 yeni yollar açarken unutulabilirdi.
      // Aşağıda her yolun isteği tek tek doğrulanıyor:
      //   * `DiaryRepository.fetchDaily`  → 3 sorgu (`deleted_at=is.null`)
      //   * `FoodRepository.search`       → `.isFilter('deleted_at', null)`
      //   * `FoodRepository.frequentFoods`→ `.isFilter('deleted_at', null)`
      //   * `FoodRepository.recents`      → `.isFilter('deleted_at', null)`
      // `favorites()` **meal_entries'e dokunmuyor** (`favorite_foods`
      // tablosunda `deleted_at` kolonu yok) — 2. grupta doğrulanıyor.
      final log = CallLog();
      final repo = FoodRepository(_client(log));

      await repo.search('u1', 'tavuk');
      await repo.frequentFoods('u1');
      await repo.recents('u1');

      final mealReads = log.requests
          .where((r) => r.url.path.endsWith('meal_entries'))
          .toList();
      expect(mealReads, hasLength(3));
      for (final r in mealReads) {
        expect(r.url.queryParameters['deleted_at'], 'is.null',
            reason: '${r.url.queryParameters['select']} yolu süzgeçsüz');
      }
    });

    // =================================================================
    // 2) ⭐ `favorites()` — sunucu + istemci katmanı elemesi
    // =================================================================
    group('2) favorites() — deleted_at + kolon sözleşmesi', () {
      test('istek doğru tabloyu, doğru filtreyi, doğru kolonları ister',
          () async {
        final log = CallLog();
        final repo = FoodRepository(_client(log, rows: const []));

        final items = await repo.favorites('u1');

        expect(items, isEmpty);
        expect(log.requests, hasLength(1));
        final r = log.requests.single;
        expect(r.url.path, endsWith('/favorite_foods'));
        expect(r.url.queryParameters['user_id'], 'eq.u1');
        expect(r.url.queryParameters['limit'], '200',
            reason: 'favoriteScanLimit web parity (eski türetilmiş tarama)');
        // supabase 2.x `order()` varsayılanı `nullsLast` ekler.
        expect(r.url.queryParameters['order'], 'created_at.desc.nullslast');
        // Besin satırı join'i **zorunlu**: `food_nutrition` olmayan gıda
        // listede 0 kcal olarak düşmemeli (`_favoriteToItem → null`).
        expect(r.url.queryParameters['select'], contains('food_nutrition'));
        expect(r.url.queryParameters['select'], contains('kcal'));
        expect(r.url.queryParameters['select'], contains('protein_g'));
      });

      test('⭐ `favorite_foods` tablosunda `deleted_at` KOLONU YOK → süzgeç '
          'yazılmamalı (yazılırsa PostgREST 400 döner)', () async {
        // `full_setup.sql:185-192`: `favorite_foods(user_id, food_id,
        // created_at)` — yumuşak silme yalnız `meal_entries`,
        // `water_entries`, `weight_entries`, `chat_messages` tablolarında.
        // `FoodRepository` sınıf dokümanında da bu açıkça yazılı
        // (`food_repository.dart:133-139`).
        final log = CallLog();
        final repo = FoodRepository(_client(log, rows: const []));
        await repo.favorites('u1');
        final select = log.requests.single.url.queryParameters['select'] ?? '';
        expect(select, isNot(contains('deleted_at')),
            reason: 'kolon tabloda yok → istenirse PGRST204 400');
      });

      test('gıdası olmayan favori satırı listede düşmez (yarım kayıt yok)', () async {
        final log = CallLog(rows: const [
          // `foods` join'i boş (FK NOT NULL ama savunma-derinliği).
          {
            'food_id': 'f1',
            'created_at': '2026-09-01T10:00:00Z',
          },
        ]);
        final repo = FoodRepository(_client(log));

        final items = await repo.favorites('u1');

        expect(items, isEmpty,
            reason: 'besin satırı olmayan gıda 0 kcal olarak listelenmemeli');
      });

      test('⭐ liste 10 öğeyle kesilir (favoriteDisplayLimit) — 200 tarama '
          'penceresinden bağımsız', () async {
        final log = CallLog(rows: List.generate(
          25,
          (i) => {
            'food_id': 'f$i',
            'created_at': '2026-09-${(i + 1).toString().padLeft(2, '0')}T10:00:00Z',
            'foods': {
              'id': 'f$i',
              'name': 'Yemek $i',
              'brand': null,
              'serving_size_g': 100.0,
              'food_nutrition': {
                'kcal': 100.0,
                'protein_g': 10.0,
                'carbs_g': 12.0,
                'fat_g': 3.0,
              },
            },
          },
        ));
        final repo = FoodRepository(_client(log));

        final items = await repo.favorites('u1');

        expect(items, hasLength(FoodRepository.favoriteDisplayLimit));
        expect(FoodRepository.favoriteDisplayLimit, 10);
        // İlk yazan kazanır: created_at desc → en yeni gıda önce.
        expect(items.first.name, 'Yemek 0');
      });
    });

    // =================================================================
    // 3) `recent_foods` / `favorite_foods` yazma yolları
    // =================================================================
    group('3) favori yazma yolları — gövde sözleşmesi', () {
      test('addFavorite: user_id + food_id yazılır, created_at YAZILMAZ', () async {
        final log = CallLog();
        final repo = FoodRepository(_client(log));

        await repo.addFavorite('u1', 'f1');

        final r = log.requests.single;
        expect(r.method, 'POST');
        // RLS `WITH CHECK (auth.uid() = user_id)` → `user_id` **her** kayıtta
        // yazılmalı; gövdeden düşerse NOT NULL ihlali 400 döner.
        final body = _body(r);
        expect(body['user_id'], 'u1');
        expect(body['food_id'], 'f1');
        // `created_at` DB `DEFAULT now()`'la dolar; istemciden gönderilmesi
        // A2r5'in "created_at sözleşmeye girmiyordu" hatasının aynısı.
        expect(body.containsKey('created_at'), isFalse);
        // `on_conflict` → idempotent upsert (çift dokunma 23505 üretmez).
        expect(r.url.queryParameters['on_conflict'], 'user_id,food_id');
      });

      test('removeFavorite: DELETE kullanıcı kapsamıyla', () async {
        final log = CallLog();
        final repo = FoodRepository(_client(log));

        await repo.removeFavorite('u1', 'f1');

        final r = log.requests.single;
        expect(r.method, 'DELETE');
        expect(r.url.path, endsWith('/favorite_foods'));
        expect(r.url.queryParameters['user_id'], 'eq.u1');
        expect(r.url.queryParameters['food_id'], 'eq.f1');
      });

      test('favoriteIds: TEK sorguda küme döner (N+1 yok)', () async {
        final log = CallLog(rows: const [
          {'food_id': 'a'},
          {'food_id': 'b'},
        ]);
        final repo = FoodRepository(_client(log));

        final ids = await repo.favoriteIds('u1');

        expect(ids, {'a', 'b'});
        expect(log.requests, hasLength(1));
        expect(log.requests.single.url.queryParameters['select'], 'food_id');
      });

      test('favoriteIds: null food_id satırı küme kirletmez', () async {
        final log = CallLog(rows: const [
          {'food_id': 'a'},
          {'food_id': null},
        ]);
        final ids = await FoodRepository(_client(log)).favoriteIds('u1');
        expect(ids, {'a'});
      });
    });

    // =================================================================
    // 4) `deleteFood` — silme sırası + RLS kapsamı
    // =================================================================
    group('4) deleteFood — gıda önce silinir, favoriler sonra', () {
      test('gıda silinemezse (0 satır) favori satırlarına DOKUNULMAZ', () async {
        final log = CallLog(deleteRows: const []);
        final repo = FoodRepository(_client(log));

        final ok = await repo.deleteFood('u1', 'f1');

        expect(ok, isFalse, reason: 'sessiz "başarı" olmaz');
        // Yalnızca `foods` DELETE atıldı; `favorite_foods` **dokunulmadı**
        // (yarım sonuç: "favoriler silindi ama gıda silinemedi").
        expect(log.requests.map((r) => r.url.path.split('/').last),
            ['foods']);
      });

      test('gıda silinince favoriler de temizlenir (2 istek, sıra doğru)', () async {
        final log = CallLog(deleteRows: const [
          {'id': 'f1'},
        ]);
        final repo = FoodRepository(_client(log));

        final ok = await repo.deleteFood('u1', 'f1');

        expect(ok, isTrue);
        expect(log.requests, hasLength(2));
        expect(log.requests[0].url.path, endsWith('/foods'));
        expect(log.requests[1].url.path, endsWith('/favorite_foods'));
        // `foods` DELETE'i kullanıcı kapsamıyla (RLS `created_by = auth.uid()`).
        expect(log.requests[0].url.queryParameters['created_by'], 'eq.u1');
        expect(log.requests[0].url.queryParameters['id'], 'eq.f1');
      });
    });

    // =================================================================
    // 5) `fetchDaily` — sınırlar ve nullable alanlar
    // =================================================================
    group('5) fetchDaily kenar durumları', () {
      test('üç sorgu paralel: öğün, su ve EN SON KİLO', () async {
        final log = CallLog(rows: const []);
        final repo = DiaryRepository(_client(log));

        final data = await repo.fetchDaily('u1', DateTime(2026, 8, 15));

        expect(data.mealEntries, isEmpty);
        expect(data.waterEntries, isEmpty);
        expect(data.latestWeight, isNull);
        expect(log.requests, hasLength(3));
        final paths = log.requests.map((r) => r.url.path.split('/').last).toSet();
        expect(paths, {'meal_entries', 'water_entries', 'weight_entries'});
        // Üçü de `deleted_at IS NULL` süzgecini sunucuya gönderiyor.
        for (final r in log.requests) {
          expect(r.url.queryParameters['deleted_at'], 'is.null');
        }
        // `entry_date` yerel gün (`yyyy-MM-dd`).
        expect(log.requests[0].url.queryParameters['entry_date'],
            'eq.2026-08-15');
      });

      test('kilo sorgusu `deleted_at` alanını da getirir (istemci elemesi için)',
          () async {
        final log = CallLog();
        await DiaryRepository(_client(log)).fetchDaily('u1', DateTime(2026, 8, 15));
        // `select()` **tüm** kolonları getirir (`select=*`) → `deleted_at`
        // dâhil, yani istemci elemesi mümkündür. (supabase 2.x `select()`
        // çağrısız → `*`.)
        final weightReq =
            log.requests.firstWhere((r) => r.url.path.endsWith('weight_entries'));
        expect(weightReq.url.queryParameters['select'], '*',
            reason: 'select() tüm kolonları getirir → deleted_at dâhil');
      });

      test('⭐ silinmiş öğün gün toplamına GİRMEZ (defansif eleme)', () async {
        // Sunucu süzgeci uygulamasa bile istemci elemesi devrede.
        final log = CallLog(
          meals: [
            {
              'id': 'm1',
              'user_id': 'u1',
              'meal_type': 'lunch',
              'amount_g_ml': 100.0,
              'calculated_kcal': 500.0,
              'calculated_protein': 30.0,
              'calculated_carbs': 40.0,
              'calculated_fat': 10.0,
              'entry_date': '2026-08-15',
              'source': 'manual',
              'created_at': '2026-08-15T12:00:00Z',
              'updated_at': null,
              'deleted_at': null,
              'food_id': null,
              'custom_name': 'Tavuk',
              'note': null,
              'photo_url': null,
            },
            {
              'id': 'm2',
              'user_id': 'u1',
              'meal_type': 'dinner',
              'amount_g_ml': 100.0,
              'calculated_kcal': 999.0,
              'calculated_protein': 0.0,
              'calculated_carbs': 0.0,
              'calculated_fat': 0.0,
              'entry_date': '2026-08-15',
              'source': 'manual',
              'created_at': '2026-08-15T19:00:00Z',
              'updated_at': null,
              // Sunucu süzgecini uygulamış gibi düşünüp eleme **kalkmış**:
              // burada satır silinmiş olarak dönüyor.
              'deleted_at': '2026-08-15T20:00:00Z',
              'food_id': null,
              'custom_name': 'Silinmiş yemek',
              'note': null,
              'photo_url': null,
            },
          ],
        );
        final data = await DiaryRepository(_client(log))
            .fetchDaily('u1', DateTime(2026, 8, 15));

        expect(data.mealEntries, hasLength(1));
        expect(data.totals.calories, 500,
            reason: 'silinmiş öğün toplama girmemeli');
        expect(data.totals.calories, isNot(1499));
      });

      test('bozuk satır tüm günü düşürmez (satır atlanır, gün boş kalır)', () async {
        // `MealEntry.fromJson` zorlaması (`as String`) bozuk satırda patlar;
        // `_mapRows` satırı atlayıp diğerlerini korur.
        final log = CallLog(
          meals: [
            {'id': 'bozuk', 'meal_type': null},
          ],
        );
        final data = await DiaryRepository(_client(log))
            .fetchDaily('u1', DateTime(2026, 8, 15));
        expect(data.mealEntries, isEmpty);
        expect(data.totals.calories, 0);
      });
    });

    // =================================================================
    // 6) Saf yardımcılar: null güvenliği
    // =================================================================
    group('6) saf yardımcılar — null güvenliği', () {
      test('customItem: miktar null/NaN/negatif → 100g varsayılanı', () {
        // `x / 0` → Infinity → `round()` **istisna** fırlatırdı
        // (A2r3'in düzelttiği hata). Üç giriş de güvenli.
        for (final amount in <Object?>[null, double.nan, 0.0, -5.0]) {
          final item = FoodRepository.customItem({
            'id': 'm1',
            'custom_name': 'Tavuk',
            'amount_g_ml': amount,
            'calculated_kcal': 500.0,
            'calculated_protein': 30.0,
            'calculated_carbs': 40.0,
            'calculated_fat': 10.0,
          });
          expect(item.servingSizeG, 100.0, reason: 'amount=$amount');
          // 500 kcal / 100 g × 100 = 500
          expect(item.calories, 500.0);
        }
      });

      test('customItem: besin değeri null → 0 (NaN yayılmaz)', () {
        final item = FoodRepository.customItem({
          'id': 'm1',
          'custom_name': 'X',
          'amount_g_ml': 100.0,
          'calculated_kcal': null,
          'calculated_protein': null,
          'calculated_carbs': null,
          'calculated_fat': null,
        });
        expect(item.calories, 0.0);
        expect(item.proteinG, 0.0);
      });

      test('customItem: isim null → "Bilinmeyen" (as String patlamaz)', () {
        final item = FoodRepository.customItem({'id': 'm1', 'amount_g_ml': 100.0});
        expect(item.name, 'Bilinmeyen');
      });

      test('isUsableAmount: 0/negatif/NaN/Infinity reddedilir, pozitif geçer', () {
        expect(DiaryRepository.isUsableAmount(0), isFalse);
        expect(DiaryRepository.isUsableAmount(-0.0), isFalse);
        expect(DiaryRepository.isUsableAmount(-1), isFalse);
        expect(DiaryRepository.isUsableAmount(double.nan), isFalse);
        expect(DiaryRepository.isUsableAmount(double.infinity), isFalse);
        expect(DiaryRepository.isUsableAmount(null), isFalse);
        expect(DiaryRepository.isUsableAmount(0.5), isTrue);
        expect(DiaryRepository.isUsableAmount(10000), isTrue);
      });
    });
  });
}

/// İstek günlüğü + sahte DB.
class CallLog {
  CallLog({
    this.rows = const [],
    this.meals = const [],
    this.waters = const [],
    this.weights = const [],
    this.deleteRows = const [],
  });

  final List<http.Request> requests = <http.Request>[];

  /// Varsayılan yanıt (yapılandırılmamış GET'ler için).
  final List<Map<String, dynamic>> rows;

  /// `fetchDaily` öğün yanıtı.
  final List<Map<String, dynamic>> meals;

  /// `fetchDaily` su yanıtı.
  final List<Map<String, dynamic>> waters;

  /// `fetchDaily` kilo yanıtı (tek satır).
  final List<Map<String, dynamic>> weights;

  /// DELETE dönüş satırları.
  final List<Map<String, dynamic>> deleteRows;
}

Map<String, dynamic> _body(http.Request r) {
  final decoded = jsonDecode(r.body);
  // supabase 2.x toplu `upsert` gövdesini **tek nesne** olarak gönderir.
  return decoded as Map<String, dynamic>;
}

SupabaseClient _client(
  CallLog log, {
  List<Map<String, dynamic>> rows = const [],
}) {
  return SupabaseClient(
    'https://test.supabase.co',
    'anon-key',
    httpClient: MockClient((req) async {
      log.requests.add(req);
      final table = req.url.path.split('/').last;

      if (req.method == 'DELETE') {
        return _respond(req, log.deleteRows);
      }
      if (req.method == 'POST') {
        return _respond(req, const <Object>[]);
      }
      if (req.method == 'PATCH') {
        return _respond(req, const <Object>[]);
      }

      // GET
      final body = switch (table) {
        'meal_entries' => log.meals,
        'water_entries' => log.waters,
        'weight_entries' => log.weights,
        _ => rows.isNotEmpty ? rows : log.rows,
      };
      // `maybeSingle()` kullanılan kilo sorgusu tek satır bekler.
      final hasLimit = req.url.queryParameters['limit'] == '1';
      if (hasLimit) {
        return _respond(req, body.isEmpty ? null : body.first);
      }
      return _respond(req, body);
    }),
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
  );
}

http.Response _respond(http.BaseRequest request, Object? body) =>
    http.Response(
      body == null ? 'null' : jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
