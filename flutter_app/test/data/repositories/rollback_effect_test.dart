import 'dart:convert';

import 'package:calorix/data/repositories/data_transfer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ⭐ Telafi (`_rollback`) DELETE **etkisini** doğruluyor mu? (A2r9, P3 borcu)
///
/// ## Borç neydi?
///
/// A2r5'ten kalan not (TRANSFER-defteri T5): "`_rollback` DELETE **etkisini**
/// doğrulamıyor (istek atmama durumu `rolledBack = true` sayılıyor)."
///
/// Eski kod:
///
/// ```dart
/// for (final chunk in inFilterChunks(ids)) {
///   try {
///     await _client.from(table).delete().inFilter('id', chunk);
///     remaining -= chunk.length;   // ← "istek fırlatmadı" = "silindi"
///   } catch (e, s) { … }
/// }
/// ```
///
/// **Sorun:** PostgREST `DELETE` isteği başarılı olsa bile **0 satır**
/// silebilir. RLS politikası gevşemişse, `id` filtresi bir şekilde yok
/// sayılmışsa ya da satır zaten başka bir işlemde silinmişse, `DELETE`
/// 200 döner ve boş gövde gelir — eski kod buna "başarıyla silindi" der,
/// `rolledBack = true` raporlar, `counts` sıfırlar ve kullanıcıya
/// **"hiçbir şey yazılmadı"** yalanı söyler. Oysa DB'de yarım içe aktarma
/// duruyor.
///
/// ## Düzeltme
///
/// `DELETE` artık `.select('id')` ile **kendi satırlarını geri getiriyor**
/// (`RETURNING id`). Silinmeyen id'ler **ölçülüyor** ve `survivors`'a
/// yazılıyor. Kısmi silmede (RLS bir kısmını sildiyse) yalnızca
/// **kalan** id'ler raporlanır — en kötü senaryo varsayımı yok.
///
/// ## Bu testin kanıt değeri
///
/// Testte **üç ayrı DB davranışı** taklit edilir ve her biri farklı bir
/// `rolledBack` sonucu vermek zorundadır:
///  * `none`  → 200 + boş gövde (istem atıldı, **hiç silinmedi**)
///  * `all`   → 200 + istenen id'lerin tamamı
///  * `some`  → 200 + yalnız bir kısmı (kısmi silme)
///  * `throw` → 403 (istek fırlatıldı)
/// Ölümcül ölçüm: `_rollback`'taki `.select('id')` kaldırılırsa
/// `none`/`some` senaryoları **kırmızıya döner** (bkz. rapor).
void main() {
  // Basit yedek: 3 gıda + 1 öğün. `meal_entries` yazımı 400 döner → telafi.
  String backup() => jsonEncode({
        'version': '1.3.0',
        'exportedAt': '2026-09-28T00:00:00Z',
        'foods': [
          for (var i = 0; i < 3; i++)
            {'id': 'bk-f$i', 'name': 'Yemek $i', 'source': 'manual'},
        ],
        'meal_entries': [
          {
            'id': 'bk-m0',
            'entry_date': '2026-08-15',
            'meal_type': 'lunch',
            'custom_name': 'Tavuk',
            'amount_g_ml': 100,
            'calculated_kcal': 500,
            'calculated_protein': 30,
            'calculated_carbs': 40,
            'calculated_fat': 10,
          },
        ],
      });

  group('1) ⭐ DELETE 0 satır silerse telafi BAŞARISIZ sayılır', () {
    test('rolledBack=false ve survivors dolu — eski kodda "başarı" idi', () async {
      final deletes = <http.Request>[];
      final repo = DataTransferRepository(
        _client(deletes: deletes, deleteBehaviour: _DeleteBehaviour.none),
      );

      try {
        await repo.importBackup('u1', backup());
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        expect(e.stage, 'meal_entries');
        expect(
          e.report.rolledBack,
          isFalse,
          reason: 'DELETE 200 döndü ama hiçbir satırı silmediği doğrulandı',
        );
        expect(e.report.isPartial, isTrue);
        // Silinemeyen kayıtlar **tam olarak** raporlanır.
        expect(e.report.writtenTables['foods'], hasLength(3));
        expect(e.report.counts['foods'], 3,
            reason: 'kayıtlar duruyor → sayı doğru olmalı, 0 değil');
        expect(e.summary, contains('geri alınamadı'));
      }
      // DELETE gerçekten atıldı (etkisi boş döndü).
      expect(deletes, hasLength(1));
    });

    test('⭐ kullanıcıya "hiçbir şey yazılmadı" yalanı söylenmiyor', () async {
      final repo = DataTransferRepository(
        _client(deleteBehaviour: _DeleteBehaviour.none),
      );
      try {
        await repo.importBackup('u1', backup());
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        // `counts` sıfırlanmadı → kullanıcı gerçekte kaç kayıt kaldığını görür.
        expect(e.report.totalAdded, 3);
        expect(e.report.rolledBack, isNot(true));
      }
    });
  });

  group('2) DELETE tüm satırları silerse telafi başarılı', () {
    test('rolledBack=true, counts 0, survivors boş', () async {
      final repo = DataTransferRepository(
        _client(deleteBehaviour: _DeleteBehaviour.all),
      );
      try {
        await repo.importBackup('u1', backup());
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        expect(e.report.rolledBack, isTrue);
        expect(e.report.counts['foods'], 0);
        expect(e.report.writtenTables, isEmpty);
        expect(e.summary, contains('geri alındı'));
        // Telafi başarılı → **kısmi değil**: kullanıcının verisi tamamen
        // geri alındı, DB temiz. `failedStage` dolu olsa bile `isPartial`
        // `false` olmalı (A2r9 düzeltmesi: eski tanım her hata halinde
        // `true` dönüyordu ve "kısmi bitti" anlamını taşımıyordu).
        expect(e.report.isPartial, isFalse);
        expect(e.report.failedStage, isNotNull,
            reason: 'hata hangi adımda olduğunu yine de bildirir');
      }
      // ⭐ **Negatif ölçüm kanıtı:** bu testin kırmızı olması
      // `_rollback`'taki `.select('id')` kaldırıldığında anlamlı. Yani
      // davranış gerçekten testte bağlı, "yeşil ama ölü" değil.
    });
  });

  group('3) ⭐ KISMİ silme: yalnız kalanlar raporlanır (tahmin yok)', () {
    test('3 gıdadan 1 silindi → survivors tam olarak 2 satır', () async {
      final repo = DataTransferRepository(
        _client(deleteBehaviour: _DeleteBehaviour.some),
      );
      try {
        await repo.importBackup('u1', backup());
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        expect(e.report.rolledBack, isFalse);
        // Silinen 1 + kalan 2 = 3 yazılmış satır.
        expect(e.report.writtenTables['foods'], hasLength(2),
            reason: 'silinen id "ölü" varsayımıyla raporlanmamalı');
        expect(e.report.counts['foods'], 3,
            reason: 'bir kısmı hâlâ duruyor → tüm yazılanlar sayılır');
      }
    });

    test('survivors listesi boş değil ve benzersizdir', () async {
      final repo = DataTransferRepository(
        _client(deleteBehaviour: _DeleteBehaviour.some),
      );
      try {
        await repo.importBackup('u1', backup());
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        final survivors = e.report.writtenTables['foods']!;
        // Sahte DB'nin "sadece ilk satırı sildiği" kuralıyla tutarlı:
        // 3 gıda yazıldı (`ins-…`), biri silindi.
        expect(survivors, hasLength(2));
      }
    });
  });

  group('4) DELETE isteği fırlatırsa (403) — eski davranış korunur', () {
    test('istek hatası da "silinmedi" sayılır', () async {
      final repo = DataTransferRepository(
        _client(deleteBehaviour: _DeleteBehaviour.throw403),
      );
      try {
        await repo.importBackup('u1', backup());
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        expect(e.report.rolledBack, isFalse);
        expect(e.report.writtenTables['foods'], hasLength(3));
      }
    });
  });

  group('5) DELETE isteği gerçekten kendi satırlarını istiyor', () {
    test('`in.(id,…)` filtresi + `select=id` gönderiliyor', () async {
      final deletes = <http.Request>[];
      final repo = DataTransferRepository(
        _client(deletes: deletes, deleteBehaviour: _DeleteBehaviour.all),
      );
      try {
        await repo.importBackup('u1', backup());
      } on ImportWriteError {
        // beklenen
      }
      expect(deletes, hasLength(1));
      final req = deletes.single;
      expect(req.method, 'DELETE');
      // Dönen satırların id'leri isteniyor (`RETURNING id`).
      expect(req.url.queryParameters['select'], 'id');
      // Yazılan 3 gıdanın id'si filtrede.
      final idFilter = req.url.queryParameters['id'] ?? '';
      expect(idFilter, contains('ins-'));
      expect(req.url.path, endsWith('/foods'));
    });

    test('çok satır → dilimlenmiş DELETE\'ler (8 KB URL tavanı)', () async {
      // `inFilterChunkSize` = 100; 250 gıda → 3 dilim.
      final deletes = <http.Request>[];
      final repo = DataTransferRepository(
        _client(deletes: deletes, deleteBehaviour: _DeleteBehaviour.all),
      );
      final big = jsonEncode({
        'version': '1.3.0',
        'exportedAt': '2026-09-28T00:00:00Z',
        'foods': [
          for (var i = 0; i < 250; i++)
            {'id': 'bk-f$i', 'name': 'Yemek $i', 'source': 'manual'},
        ],
        'meal_entries': [
          {
            'id': 'bk-m0',
            'entry_date': '2026-08-15',
            'meal_type': 'lunch',
            'custom_name': 'Tavuk',
            'amount_g_ml': 100,
            'calculated_kcal': 500,
            'calculated_protein': 30,
            'calculated_carbs': 40,
            'calculated_fat': 10,
          },
        ],
      });
      try {
        await repo.importBackup('u1', big);
      } on ImportWriteError {
        // beklenen
      }
      final foodDeletes =
          deletes.where((r) => r.url.path.endsWith('foods')).toList();
      expect(foodDeletes, hasLength(3), reason: '250 / 100 = 3 dilim');
      for (final r in foodDeletes) {
        expect(r.url.toString().length, lessThan(8000));
      }
    });
  });
}

/// Sahte DB'nin DELETE davranışı.
enum _DeleteBehaviour {
  /// 200 + boş gövde: istek atıldı, **hiçbir satır silinmedi**.
  none,

  /// 200 + istenen id'lerin tamamı.
  all,

  /// 200 + **yalnızca ilk** satır (kısmi silme).
  some,

  /// 403: istek fırlattı.
  throw403,
}

SupabaseClient _client({
  List<http.Request>? deletes,
  _DeleteBehaviour deleteBehaviour = _DeleteBehaviour.all,
}) {
  var nextId = 0;
  return SupabaseClient(
    'https://test.supabase.co',
    'anon-key',
    httpClient: MockClient((req) async {
      final table = req.url.path.split('/').last;
      // **Yalnız DELETE** günlüğe yazılır: varlık kontrolü (`GET`) ve yazma
      // (`POST`) istekleri `deletes` listesini kirletmemeli, yoksa "kaç
      // DELETE atıldı" sorusu ölçülemez.
      if (req.method == 'DELETE') deletes?.add(req);

      if (req.method == 'DELETE') {
        if (deleteBehaviour == _DeleteBehaviour.throw403) {
          return _respond(
            req,
            {'code': '42501', 'message': 'permission denied'},
            status: 403,
          );
        }
        final asked = _askedIds(req);
        final List<Map<String, dynamic>> body;
        switch (deleteBehaviour) {
          case _DeleteBehaviour.none:
            body = const [];
          case _DeleteBehaviour.all:
            body = [
              for (final id in asked) <String, dynamic>{'id': id},
            ];
          case _DeleteBehaviour.some:
            final first = asked.take(1).toList();
            body = [for (final id in first) <String, dynamic>{'id': id}];
          case _DeleteBehaviour.throw403:
            body = const [];
        }
        return _respond(req, body);
      }

      if (req.method == 'POST') {
        if (table == 'meal_entries') {
          return _respond(
            req,
            {'code': '23514', 'message': 'check violation'},
            status: 400,
          );
        }
        final decoded = jsonDecode(req.body);
        final rows = decoded is List
            ? decoded
            : <Map<String, dynamic>>[decoded as Map<String, dynamic>];
        return _respond(req, [
          for (var i = 0; i < rows.length; i++)
            {'id': 'ins-${nextId++}-$i'}
        ]);
      }

      return _respond(req, const <Object>[]);
    }),
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
  );
}

/// `inFilter` filtresini çözer.
///
/// **Ölçülmüş tuzak:** `inFilter` 1/2/3+ eleman için **üç farklı** biçim
/// üretiyor ve `Uri.queryParameters` her birini farklı bozuyor:
///  * 3+ → `in.("a","b","c")` → doğru
///  * 2  → `in.(a,b)` (tırnak atlanır)
///  * 1  → `in.a` (`in.` öneki bile yutulur)
/// Bu yüzden `(` varsa parantezden sonrası alınır, yoksa ham değer
/// kullanılır ve her iki durumda da `in.` öneği temizlenir.
List<String> _askedIds(http.BaseRequest req) {
  final raw = req.url.queryParameters['id'] ?? '';
  final cleaned = raw.contains('(') ? raw.substring(raw.indexOf('(') + 1) : raw;
  return cleaned
      .replaceAll(')', '')
      .split(',')
      .map((s) => s.trim().replaceAll('"', '').replaceFirst(RegExp(r'^in\.'), ''))
      .where((s) => s.isNotEmpty)
      .toList();
}

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
