import 'dart:convert';

import 'package:calorix/data/repositories/data_transfer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gerçek `SupabaseClient` + sahte HTTP katmanı — `MockClient` isteği
/// yanıtta taşımadığı için `request` ilişkisi geri kurulur
/// (postgrest `_parseResponse`, `postgrest_builder.dart:462`).
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

/// Gerçekçi bir yedek üretir. Varsayılan 2000 öğün / 2000 su / 400 kilo /
/// 40 gıda — yani "6 aylık aktif kullanıcı" senaryosu.
String backupJson({
  int meals = 10,
  int waters = 10,
  int weights = 10,
  int foods = 3,
  int nutritionPerFood = 1,
  Map<String, List<Map<String, dynamic>>>? extra,
}) {
  final payload = <String, dynamic>{
    'version': '1.3.0',
    'exportedAt': '2026-09-28T00:00:00Z',
    if (foods > 0)
      'foods': [
        for (var i = 0; i < foods; i++)
          {'id': 'bk-f$i', 'name': 'Yemek $i', 'source': 'manual'},
      ],
    if (foods > 0 && nutritionPerFood > 0)
      'food_nutrition': [
        for (var i = 0; i < foods; i++)
          for (var n = 0; n < nutritionPerFood; n++)
            {
              'food_id': 'bk-f$i',
              'kcal': 100.0 + n,
              'protein_g': 10.0,
              'carbs_g': 12.0,
              'fat_g': 3.0,
            }
      ],
    if (meals > 0)
      'meal_entries': [
        for (var i = 0; i < meals; i++)
          {
            'id': 'bk-m$i',
            'user_id': 'başka-kullanıcı',
            'entry_date': _day(i),
            'meal_type': 'lunch',
            'custom_name': 'Öğün $i',
            'amount_g_ml': 100,
            'calculated_kcal': 500,
            'calculated_protein': 30,
            'calculated_carbs': 40,
            'calculated_fat': 10,
            'created_at': '2026-03-${(1 + i % 28).toString().padLeft(2, '0')}T12:00:00Z',
          }
      ],
    if (waters > 0)
      'water_entries': [
        for (var i = 0; i < waters; i++)
          {
            'id': 'bk-w$i',
            'user_id': 'başka-kullanıcı',
            'entry_date': _day(i),
            'entry_time': _waterTime(i),
            'amount_ml': 250,
          }
      ],
    if (weights > 0)
      'weight_entries': [
        for (var i = 0; i < weights; i++)
          {
            'id': 'bk-g$i',
            'user_id': 'başka-kullanıcı',
            'entry_date': _weightDay(i),
            'weight_kg': 80.0,
          }
      ],
    ...?extra,
  };
  return jsonEncode(payload);
}

/// Öğün/su kayıtları için benzersiz gün. 2000 kayıt için 5+ yıl kullanılır
/// (gün + öğün + isim bileşimi zaten benzersiz olmalı).
String _day(int i) =>
    DateTime.utc(2026, 1, 1 + i ~/ 4).toIso8601String().split('T').first;

/// Kilo kayıtları için benzersiz gün (yıllara yayılır → benzersiz).
String _weightDay(int i) {
  final year = 2024 + i ~/ 400;
  final rest = i % 400;
  return DateTime.utc(year, 1 + rest ~/ 28, 1 + rest % 28)
      .toIso8601String()
      .split('T')
      .first;
}

/// Su kayıtları için benzersiz ve **geçerli** ISO damga.
String _waterTime(int i) {
  final day = i ~/ 250;
  final hour = (i % 250) ~/ 10;
  final minute = (i % 250) % 10;
  return DateTime.utc(2026, 1, 1 + day, hour, minute, i % 60).toIso8601String();
}

Map<String, dynamic> mealRow({
  String id = 'm1',
  String date = '2026-08-15',
  String type = 'lunch',
  String? name = 'Tavuk',
  Object? amount = 100,
  Object? kcal = 500,
  Object? protein = 30,
  Object? carbs = 40,
  Object? fat = 10,
  Object? foodId,
  Object? source = 'manual',
  Object? deletedAt,
}) =>
    {
      'id': id,
      'user_id': 'başka-kullanıcı',
      'entry_date': date,
      'meal_type': type,
      'custom_name': name,
      'amount_g_ml': amount,
      'calculated_kcal': kcal,
      'calculated_protein': protein,
      'calculated_carbs': carbs,
      'calculated_fat': fat,
      'source': source,
      'food_id': ?foodId,
      'deleted_at': ?deletedAt,
    };

/// İstek günlüğü — "hangi yola ne zaman kaç istek" sorusunu yanıtlar.
class CallLog {
  final List<http.Request> requests = <http.Request>[];

  int get getCount => requests.where((r) => r.method == 'GET').length;
  int get postCount => requests.where((r) => r.method == 'POST').length;
  int get deleteCount => requests.where((r) => r.method == 'DELETE').length;
  int get total => requests.length;

  List<http.Request> byMethod(String method) =>
      requests.where((r) => r.method == method).toList();

  List<http.Request> get posts => byMethod('POST');

  /// `POST /<tablo>` gövdeleri (tek tek satır listesi hâlinde çözülmüş).
  List<List<Map<String, dynamic>>> get insertedRows => [
        for (final r in posts)
          (jsonDecode(r.body) as List).cast<Map<String, dynamic>>(),
      ];

  /// Yazılan satır sayısı (tüm POST'lar).
  int get writtenRows =>
      insertedRows.fold<int>(0, (a, rows) => a + rows.length);

  http.Request? lastPostFor(String table) {
    for (final r in posts.reversed) {
      if (r.url.path.endsWith(table)) return r;
    }
    return null;
  }

  bool hasPostFor(String table) => lastPostFor(table) != null;
}

/// Test istemcisi.
///
/// [onPost] verilirse tablo bazında hata simüle edilebilir (yazma hatası
/// senaryoları). [onDeleteFail] telafinin başarısız olmasını simüle eder.
SupabaseClient clientWith(
  CallLog log, {
  Map<String, List<Map<String, dynamic>>> existing = const {},
  Set<String>? failPostFor,
  bool failDelete = false,
  String userId = 'u1',
}) {
  var nextId = 0;
  return SupabaseClient(
    'https://test.supabase.co',
    'anon-key',
    httpClient: MockClient((req) async {
      log.requests.add(req);
      final table = req.url.path.split('/').last;

      if (req.method == 'DELETE') {
        if (failDelete) {
          return _respond(req, {'code': '42501', 'message': 'permission denied'},
              status: 403);
        }
        // A2r9: `_rollback` artık **silinen satırların id'lerini doğruluyor**
        // (`.select('id')` → `RETURNING id`). Sahte DB `in.(...)` filtresini
        // gerçekten uygular ve silinen id'leri döndürür; aksi hâlde
        // "0 satır silindi" yanıtı gelir ve telafi başarısız sayılır.
        //
        // **DİKKAT — ölçülmüş tuzak:** `inFilter` üç farklı yazım üretiyor
        // ve `Uri.queryParameters` bunları **kendisi bozar**:
        //   * 3+ eleman  → `in.("a","b","c")` → doğru parse edilir
        //   * 2 eleman   → `in.(a,b)` (tırnak atlanır, yalnız `)` bozulur)
        //   * 1 eleman   → `in.ins-0-0` → `)` **yok**, `in.` **yutulur**
        // (ölçüldü: `supabase` 2.x `PostgrestQueryBuilder`, DELETE `id` filtresi)
        // Bu yüzden yalnızca `(` ve tırnak temizlenir; `in.` öneki ise
        // ayrıştırılmadan önce **açıkça atılır** (aksi hâlde ilk eleman
        // `in.ins-0-0` olur ve hiçbir satır eşleşmez).
        final raw = req.url.queryParameters['id'] ?? '';
        final cleaned = raw.contains('(') ? raw.substring(raw.indexOf('(') + 1) : raw;
        final asked = cleaned
            .replaceAll(')', '')
            .split(',')
            .map((s) => s.trim().replaceAll('"', ''))
            .where((s) => s.isNotEmpty && s != 'in.')
            .toSet();
        return _respond(req, <Map<String, dynamic>>[
          for (final id in asked) <String, dynamic>{'id': id}
        ]);
      }

      if (req.method == 'POST') {
        if (failPostFor != null && failPostFor.contains(table)) {
          return _respond(req, {'code': '23514', 'message': 'check violation'},
              status: 400);
        }
        final decoded = jsonDecode(req.body);
        final rows = decoded is List
            ? decoded
            : <Map<String, dynamic>>[decoded as Map<String, dynamic>];
        // `.select('id')` → yazılan satırların id'leri döner (RETURNING).
        return _respond(req, [
          for (var i = 0; i < rows.length; i++) {'id': 'ins-${nextId++}-$i'}
        ]);
      }

      if (req.method == 'GET') {
        final select = (req.url.queryParameters['select'] ?? 'id')
            .split(',')
            .map((s) => s.trim())
            .toList();
        for (final entry in existing.entries) {
          if (!req.url.path.endsWith(entry.key)) continue;
          // İstenen kolonlar mevcut satırlarda yoksa bu tablo için bir şey
          // dönmek istemiyoruz (başka bir sorgu olabilir).
          if (entry.value.isNotEmpty &&
              !entry.value.first.keys.toSet().containsAll(select)) {
            continue;
          }
          return _respond(req, [
            for (final row in entry.value)
              Map<String, dynamic>.fromEntries(
                select.map((c) => MapEntry(c, row[c])),
              ),
          ]);
        }
        return _respond(req, const <Object>[]);
      }
      return _respond(req, const <Object>[]);
    }),
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
  );
}

void main() {
  // =================================================================
  // 1) "Önce doğrula, sonra yaz" — doğrulama hatasında HİÇBİR yazma yok
  // =================================================================
  group('doğrulama hatasında hiçbir yazma olmaz', () {
    test('geçersiz dosya: biçim hatası, ağ hiç çağrılmaz', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));

      await expectLater(
        repo.importBackup('u1', 'bu json değil {{{'),
        throwsA(isA<ImportFormatError>()),
      );
      expect(log.total, 0, reason: 'biçim hatası için ağ gereksiz');
    });

    test('version/exportedAt eksik → ImportFormatError (FormatException alt sınıfı)',
        () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));

      await expectLater(
        repo.importBackup('u1', jsonEncode({'foods': <Object>[]})),
        throwsA(isA<ImportFormatError>()),
      );
      // Arayüzün mevcut `on FormatException` kolu bunu yakalar.
      expect(const ImportFormatError('x'), isA<FormatException>());
      expect(log.total, 0);
    });

    test('DB kabul etmeyeceği kilo (0) → hiçbir tabloya yazılmaz', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final json = jsonEncode({
        'version': '1.3.0',
        'exportedAt': '2026-09-28T00:00:00Z',
        // Önce öğünler: eski sürümde bunlar yazılır, kilo 400'ünde import
        // ölür ve kullanıcı yarım veriyle kalırdı.
        'meal_entries': [mealRow(id: 'm1')],
        'weight_entries': [
          {'id': 'g1', 'entry_date': '2026-08-15', 'weight_kg': 0},
        ],
      });

      await expectLater(
        repo.importBackup('u1', json),
        throwsA(isA<ImportValidationError>()),
      );
      expect(log.postCount, 0, reason: 'doğrulama hatasında yazma olmaz');
      expect(log.deleteCount, 0, reason: 'telafiye de gerek yok');
    });

    test('su miktarı 0 (eski sürüm 0 yazıp DB 400 veriyordu) → ölümcül', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final json = jsonEncode({
        'version': '1.3.0',
        'exportedAt': '2026-09-28T00:00:00Z',
        'water_entries': [
          {'id': 'w1', 'entry_date': '2026-08-15', 'entry_time': '2026-08-15T10:00:00Z', 'amount_ml': 0},
        ],
      });

      await expectLater(
        repo.importBackup('u1', json),
        throwsA(isA<ImportValidationError>()),
      );
      expect(log.postCount, 0);
    });

    test('miktar 10000+ (DB CHECK üst sınırı) → ölümcül', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));

      for (final bad in <Object>[10001, -5, 0]) {
        await expectLater(
          repo.importBackup('u1', jsonEncode({
            'version': '1.3.0',
            'exportedAt': 'x',
            'meal_entries': [mealRow(amount: bad)],
          })),
          throwsA(isA<ImportValidationError>()),
          reason: 'amount_g_ml=$bad',
        );
      }
      expect(log.postCount, 0);
    });

    test('zorunlu sayısal alan string ise ölümcül (0 yazmak yanlış veriydi)',
        () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));

      await expectLater(
        repo.importBackup('u1', jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'X'},
          ],
          'food_nutrition': [
            // `kcal NOT NULL numeric` — string göndermek Postgres 400'ü.
            {'food_id': 'f1', 'kcal': 'çok', 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1},
          ],
        })),
        throwsA(isA<ImportValidationError>()),
      );
      expect(log.postCount, 0);
    });

    test('tüm ölümcül ihlaller raporda; özet ilk sorunu söyler', () async {
      final repo = DataTransferRepository(clientWith(CallLog()));
      try {
        await repo.importBackup('u1', jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'meal_entries': [
            mealRow(id: 'a', amount: 0),
            mealRow(id: 'b', date: '2026-08-16', amount: -1),
            mealRow(id: 'c', date: '2026-08-17', amount: 100),
          ],
        }));
        fail('ölümcül ihlalde import durmalıydı');
      } on ImportValidationError catch (e) {
        expect(e.issues, hasLength(2));
        expect(e.issues.every((i) => i.isFatal), isTrue);
        expect(e.issues.map((i) => i.rowId), containsAll(<String>['a', 'b']));
        expect(e.summary, contains('doğrulanamadı'));
      }
    });

    test('atlanabilir satırlar ölümcül sayılmaz (import devam eder)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': '  '}, // isimsiz → atlanır
            {'id': 'f2'}, // isim yok → atlanır
            {'id': 'f3', 'name': 'Salata'},
          ],
          'meal_entries': [
            mealRow(id: 'm1', name: null, date: '2026-08-15'),
            // Yumuşak silinmiş satır → yeniden EKLENMEZ.
            mealRow(id: 'm2', date: '2026-08-16', deletedAt: '2026-08-16T10:00:00Z'),
            // Yedekte m1 ile aynı anahtarlı ikinci kayıt → atlanır
            // (`custom_name` null, `2026-08-15`, `lunch`).
            mealRow(id: 'm3', date: '2026-08-15', name: null),
            // İkinci silinmiş satır **hiç plana girmez** (`_liveRowsOf`
            // eler) — "atlandı" sayacına da yazılmaz, çünkü bu bir
            // yedek hatası değil, kullanıcının bilinçli silmiş kaydıdır.
            mealRow(id: 'm4', date: '2026-08-16', deletedAt: '2026-08-16T10:00:00Z'),
          ],
        }),
      );

      expect(report.counts['foods'], 1);
      expect(report.counts['meal_entries'], 1);
      expect(report.skipped['foods'], 2);
      expect(report.skipped['meal_entries'], 1);
      // Silinmiş kayıt DB'ye hiç sızmaz: gövdede `deleted_at` yoktur.
      final meals = log.insertedRows.firstWhere((r) => r.first.containsKey('meal_type'));
      expect(meals, hasLength(1));
      expect(meals.single.containsKey('deleted_at'), isFalse);
      expect(log.writtenRows, 2, reason: '1 gıda + 1 öğün');
    });
  });

  // =================================================================
  // 2) Doğrulama → yazma sırası: yazmadan önce tamamı kontrol edilir
  // =================================================================
  group('yazma öncesi varlık kontrolü', () {
    test('DB\'de zaten olan gıda yeniden yazılmaz, öğün ona bağlanır', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(
        log,
        existing: {
          'foods': [
            {'id': 'mevcut-1', 'name': 'Yemek 0'},
          ],
        },
      ));

      final report = await repo.importBackup('u1', backupJson(foods: 2, meals: 2, waters: 0, weights: 0));

      expect(report.counts['foods'], 1, reason: '1 gıda DB\'de vardı');
      // Besin satırı da yazılmaz: UNIQUE(food_id) ihlali olurdu.
      expect(report.counts['food_nutrition'], 1);
      expect(log.hasPostFor('foods'), isTrue);
      final meals = log.insertedRows.firstWhere((r) => r.first['user_id'] == 'u1');
      expect(meals, isNotEmpty);
    });

    test('aynı gün/öğün/yemek için DB kaydı varsa öğün tekrar yazılmaz', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(
        log,
        existing: {
          'meal_entries': [
            {'entry_date': _day(0), 'custom_name': 'Öğün 0', 'meal_type': 'lunch'},
          ],
        },
      ));

      final report = await repo.importBackup(
        'u1',
        backupJson(foods: 0, nutritionPerFood: 0, meals: 3, waters: 0, weights: 0),
      );

      expect(report.counts['meal_entries'], 2, reason: '3 öğünden 1\'i zaten vardı');
    });

    test('su dedup\'u dize değil epoch üzerinden çalışır (+00:00 ↔ Z)', () async {
      // Aynı an, farklı biçim: dize karşılaştırması dedup'ı kırardı ve aynı
      // su kaydı iki kez eklenirdi.
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(
        log,
        existing: {
          'water_entries': [
            {'entry_time': '2026-01-01T09:00:00+00:00'},
          ],
        },
      ));

      final report = await repo.importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'water_entries': [
            {
              'id': 'w1',
              'entry_date': '2026-01-01',
              'entry_time': '2026-01-01T09:00:00Z',
              'amount_ml': 250,
            },
          ],
        }),
      );

      expect(report.counts['water_entries'], 0,
          reason: 'aynı an → tekrar yazılmaz');
    });

    test('varlık sorguları 100\'lük dilimlerle gider (8 KB URL tavanı)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));

      // 300 kilo kaydı → 300 benzersiz gün → 3 dilim (100'lük).
      await repo.importBackup(
        'u1',
        backupJson(foods: 0, nutritionPerFood: 0, meals: 0, waters: 0, weights: 300),
      );

      final weightGets = log.byMethod('GET')
          .where((r) => r.url.path.endsWith('weight_entries'))
          .toList();
      expect(weightGets, hasLength(3));
      for (final r in weightGets) {
        expect(
          r.url.toString().length,
          lessThan(8000),
          reason: 'dilimli `in` URL\'i 8 KB tavanını aşmamalı',
        );
      }
    });
  });

  // =================================================================
  // 3) Yazma hatasında telafi + her zaman görünür rapor
  // =================================================================
  group('yazma hatası: telafi ve görünür sonuç', () {
    test('meal_entries 400 → foods+besin yazılmış, telafi edildi, counts 0', () async {
      final log = CallLog();
      final repo =
          DataTransferRepository(clientWith(log, failPostFor: {'meal_entries'}));

      try {
        await repo.importBackup('u1', backupJson(foods: 3, meals: 5, waters: 2, weights: 2));
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        expect(e.stage, 'meal_entries');
        expect(e.code, '23514');
        // Yazılmış kayıt sayısı **dokunulmadan** raporda.
        expect(e.report.counts['foods'], 0,
            reason: 'telafi başarılı → kullanıcının verisi kalmadı');
        expect(e.report.rolledBack, isTrue);
        expect(e.report.writtenTables, isEmpty);
        expect(e.report.failedStage, 'meal_entries');
        // Rapor HER ZAMAN doludur: yazma adımları sıfırdan başlar.
        expect(e.report.counts.keys, containsAll(<String>[
          'foods',
          'food_nutrition',
          'meal_entries',
          'water_entries',
          'weight_entries',
        ]));
      }
      // foods DELETE ile geri alınır.
      expect(log.deleteCount, greaterThan(0));
      expect(log.byMethod('DELETE').any((r) => r.url.path.endsWith('foods')),
          isTrue);
    });

    test('telafi başarısızsa kalan satırların id\'leri raporda', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(
        log,
        failPostFor: {'meal_entries'},
        failDelete: true,
      ));

      try {
        await repo.importBackup('u1', backupJson(foods: 3, meals: 5));
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        expect(e.report.rolledBack, isFalse);
        expect(e.report.counts['foods'], 3,
            reason: 'telafi edilemedi → kayıtlar duruyor, sayı doğru olmalı');
        expect(e.report.writtenTables['foods'], hasLength(3));
        expect(e.report.isPartial, isTrue);
        // Sunucu mesajı kullanıcı metnine sızmaz (kolon/kısıt adı yok).
        expect(e.summary, isNot(contains('23514')));
        expect(e.summary, isNot(contains('check violation')));
        expect(e.summary, contains('geri alınamadı'));
      }
    });

    test('foods yazımı 400 → hiçbir telafi gerekmez', () async {
      final log = CallLog();
      final repo =
          DataTransferRepository(clientWith(log, failPostFor: {'foods'}));

      await expectLater(
        repo.importBackup('u1', backupJson(foods: 2, meals: 2)),
        throwsA(isA<ImportWriteError>().having((e) => e.stage, 'stage', 'foods')),
      );
      expect(log.deleteCount, 0, reason: 'hiçbir şey yazılmadı');
    });

    test('ImportWriteError sunucu ayrıntısını loga taşır ama mesajda değil', () async {
      final log = CallLog();
      final repo =
          DataTransferRepository(clientWith(log, failPostFor: {'weight_entries'}));
      try {
        await repo.importBackup('u1', backupJson(foods: 0, nutritionPerFood: 0, meals: 1, waters: 1, weights: 1));
        fail('hata fırlatmalıydı');
      } on ImportWriteError catch (e) {
        expect(e.cause, isA<PostgrestException>());
        expect(e.summary, contains('weight_entries'));
      }
    });
  });

  // =================================================================
  // 4) Ölçek: satır satır yazma → toplu yazma
  // =================================================================
  group('ölçek — istek sayısı', () {
    test('2000 öğün + 2000 su + 400 kilo + 40 gıda: istek sayısı sabit sınıfın altında',
        () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));

      final report = await repo.importBackup('u1', backupJson(
        meals: 2000,
        waters: 2000,
        weights: 400,
        foods: 40,
      ));

      expect(report.counts['meal_entries'], 2000);
      expect(report.counts['water_entries'], 2000);
      expect(report.counts['foods'], 40);

      // Satır satır yazım: 4440 POST (regresyon kanıtı).
      // Toplu yazım: 4416 satır / 500 = 9 POST + 26 GET + 0 DELETE.
      expect(log.postCount, lessThanOrEqualTo(12),
          reason: 'POST sayısı satır sayısına bağlı olmamalı');
      expect(log.total, lessThan(50),
          reason: 'toplam istek 50\'nin altında olmalı (eskiden 4506)');
      // 2000 öğün + 2000 su + 400 kilo + 40 gıda + 40 besin satırı.
      expect(log.writtenRows, 4480, reason: 'hiçbir satır kaybolmaz');
    });

    test('importBatchSize Postgres parametre tavanının çok altında', () {
      // En geniş tablo `meal_entries` = 14 kolon. 500 × 14 = 7000 ≪ 65535.
      expect(DataTransferRepository.importBatchSize, 500);
      expect(DataTransferRepository.importBatchSize * 14, lessThan(65535));
    });

    test('tek POST\'ta birden çok satır gider (bulk insert gerçekten kullanılıyor)',
        () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup(
        'u1',
        backupJson(foods: 0, nutritionPerFood: 0, meals: 50, waters: 0, weights: 0),
      );
      expect(log.postCount, 1);
      expect(log.insertedRows.single, hasLength(50));
    });

    test('boş tabloda hiç POST atılmaz (PGRST102 koruması)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup('u1', backupJson(
        foods: 0,
        nutritionPerFood: 0,
        meals: 0,
        waters: 0,
        weights: 0,
      ));
      expect(log.postCount, 0);
      expect(log.getCount, 0, reason: 'boş `in` listesi de atılmaz');
    });

    test('toplu insert\'te tüm nesnelerin anahtar kümesi aynı (PGRST102)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup(
        'u1',
        backupJson(foods: 5, meals: 5, waters: 5, weights: 5),
      );
      for (final rows in log.insertedRows) {
        if (rows.length < 2) continue;
        final keys = rows.first.keys.toSet();
        for (final r in rows) {
          expect(r.keys.toSet(), keys,
              reason: 'PostgREST çok satırlı insert\'te anahtar kümesi eşit olmalı');
        }
      }
    });
  });

  // =================================================================
  // 5) Veri bütünlüğü: yazılan gövde DB sözleşmesine uyar
  // =================================================================
  group('yazılan gövde DB sözleşmesine uyar', () {
    test('kullanıcı adı yedekten değil oturumdan gelir', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup('u1', backupJson(foods: 1, meals: 3, waters: 2, weights: 1));

      for (final rows in log.insertedRows) {
        if (rows.first.containsKey('user_id')) {
          // Yedekte `user_id: 'başka-kullanıcı'` var; yok sayılmalı.
          expect(rows.every((r) => r['user_id'] == 'u1'), isTrue,
              reason: 'yedeğin user_id alanı yok sayılmalı');
        }
        if (rows.first.containsKey('created_by')) {
          expect(rows.every((r) => r['created_by'] == 'u1'), isTrue);
        }
      }
    });

    test('foods: verified/popularity_count yedekten kopyalanmaz', () async {
      // İkisi de sistem tarafindan türetilir; web de kopyalamaz
      // (src/hooks/useDataExport.ts:154). `increment_food_popularity`
      // trigger'ı popularity_count'u kendi artırır.
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'foods': [
          {'id': 'f1', 'name': 'X', 'verified': true, 'popularity_count': 9999},
        ],
      }));
      final row = log.insertedRows.single.single;
      expect(row.containsKey('verified'), isFalse);
      expect(row.containsKey('popularity_count'), isFalse);
      expect(row['name'], 'X');
    });

    test('geçersiz enum değerleri DB varsayılanına çekilir ve SAYILIR', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'foods': [
          {'id': 'f1', 'name': 'A', 'source': 'barcode'}, // enum\'dan düştü
        ],
        'meal_entries': [
          mealRow(id: 'm1', date: '2026-08-15', type: 'brunch'), // CHECK dışı
          mealRow(id: 'm2', date: '2026-08-16', source: 'barcode'),
        ],
      }));

      final foods = log.insertedRows.firstWhere((r) => r.first.containsKey('name'));
      expect(foods.single['source'], 'manual');
      final meals = log.insertedRows.firstWhere((r) => r.first.containsKey('meal_type'));
      expect(meals, hasLength(2));
      expect(meals.first['meal_type'], 'snack');
      expect(meals.last['source'], 'manual');
      // Düzeltmeler görünür: kullanıcı "6 öğündeki brunch snack yapıldı" bilir.
      expect(report.coerced['meal_entries.meal_type'], 1);
      expect(report.coerced['meal_entries.source'], 1);
      expect(report.coerced['foods.source'], 1);
    });

    test('küsüratlı su miktarı yuvarlanır ve SAYILIR (DB 400 vermesin)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'water_entries': [
          {
            'id': 'w1',
            'entry_date': '2026-08-15',
            'entry_time': '2026-08-15T10:00:00Z',
            'amount_ml': 250.6,
          },
        ],
      }));
      final row = log.insertedRows.singleWhere((r) => r.first.containsKey('amount_ml')).single;
      // Dart `round()` yarıdan uzağa: 250.6 → 251.
      expect(row['amount_ml'], 251);
      expect(row['amount_ml'], isA<int>(), reason: 'INTEGER kolon');
      expect(report.coerced['water_entries.amount_ml'], 1);
    });

    test('created_at yedeğin damgasıyla taşınır (toplu yazım sırayı korumaz)', () async {
      // Toplu insert'te satır sırası `created_at`'i taşımaz; damga gövdede
      // yazılır yoksa 2000 öğünün hepsi aynı `now()`'u alır ve eski
      // sürümdeki "ekleme sırası" koruması kaybolur.
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup('u1', backupJson(foods: 0, nutritionPerFood: 0, meals: 3, waters: 0, weights: 0));
      final rows = log.insertedRows.single;
      expect(rows.every((r) => r['created_at'] != null), isTrue);
      expect(rows.map((r) => r['created_at']).toSet().length, greaterThan(1),
          reason: 'her öğün kendi damgasını taşır');
    });

    test('created_at bozuksa null gönderilir (PostgREST düşürür → DB now())', () async {
      // 2000'den eski bir damga gerçekçi değildir: `null` yazılır ve
      // PostgREST `defaultToNull: true` ile alanı gövdeden **düşürür** →
      // DB `NOT NULL DEFAULT now()` devreye girer. (Boş string/bozuk string
      // göndermek `22P02` üretirdi.)
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'meal_entries': [
          {...mealRow(id: 'm1'), 'created_at': '1999-01-01T00:00:00Z'},
        ],
      }));
      expect(log.insertedRows.single.single['created_at'], isNull);
    });

    test('gelecekteki created_at yok sayılır (saat kayması koruması)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'meal_entries': [
          {
            ...mealRow(id: 'm1'),
            'created_at': DateTime.now()
                .toUtc()
                .add(const Duration(days: 400))
                .toIso8601String(),
          },
        ],
      }));
      expect(log.insertedRows.single.single['created_at'], isNull);
    });

    test('eski food_id yerine yeni gıda id\'si yazılır', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'foods': [
          {'id': 'eski-id', 'name': 'Tavuk'},
        ],
        'meal_entries': [
          mealRow(id: 'm1', foodId: 'eski-id'),
        ],
      }));
      final meals = log.insertedRows.firstWhere((r) => r.first.containsKey('meal_type'));
      final writtenFoodId = meals.single['food_id'] as String;
      expect(writtenFoodId, isNot('eski-id'),
          reason: 'yedeğin eski UUID\'si yazılmaz');
      expect(writtenFoodId, startsWith('ins-'));
    });

    test('food_nutrition yeni gıda id\'sine bağlanır', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'foods': [
          {'id': 'eski', 'name': 'Tavuk'},
        ],
        'food_nutrition': [
          {'food_id': 'eski', 'kcal': 100, 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1},
        ],
      }));
      final foods = log.insertedRows.firstWhere((r) => r.first.containsKey('name'));
      final nutrition = log.insertedRows.firstWhere((r) => r.first.containsKey('kcal'));
      final writtenId = foods.single['id'];
      // foods gövdesinde `id` **yoktur** (DB üretir) → yanıttan okunur.
      expect(nutrition.single['food_id'], isA<String>());
      expect(writtenId, isNull,
          reason: 'gövde id taşımaz; id\'yi RETURNING üretir');
    });

    test('UNIQUE(food_id) ihlali: yedekte aynı gıdaya ikinci besin satırı atlanır',
        () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'foods': [
          {'id': 'f1', 'name': 'Tavuk'},
        ],
        'food_nutrition': [
          {'food_id': 'f1', 'kcal': 100, 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1},
          {'food_id': 'f1', 'kcal': 999, 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1},
        ],
      }));
      expect(report.counts['food_nutrition'], 1);
      expect(report.skipped['food_nutrition'], 1);
    });

    test('tüm yemek satırları aynı gün/öğün/yemekse yalnızca ilki yazılır', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'meal_entries': [
          mealRow(id: 'a'),
          mealRow(id: 'b'),
          mealRow(id: 'c'),
        ],
      }));
      expect(report.counts['meal_entries'], 1);
      expect(report.skipped['meal_entries'], 2);
    });
  });

  // =================================================================
  // 6) Geriye dönük uyum: importData imzası ve sanitizeFood
  // =================================================================
  group('geriye dönük uyum', () {
    test('importData hâlâ Map<String,int> döndürüyor', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final counts = await repo.importData('u1', backupJson(foods: 2, meals: 3, waters: 1, weights: 1));
      expect(counts['foods'], 2);
      expect(counts['meal_entries'], 3);
    });

    test('importData yazma hatasında ImportWriteError yutar (catch (_) yakalar)',
        () async {
      final log = CallLog();
      final repo =
          DataTransferRepository(clientWith(log, failPostFor: {'meal_entries'}));
      Object? caught;
      try {
        await repo.importData('u1', backupJson(foods: 1, meals: 1));
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<ImportWriteError>());
      // Önceki sürüm: PostgrestException yutuluyordu, `counts` kayboluyordu.
      // Artık istisna `report` taşıyor → `transfer_dialogs.dart` gösterebilir.
      expect((caught as ImportWriteError).report.counts, isNotEmpty);
    });

    test('sanitizeFood beyaz liste sözleşmesini korur', () {
      final out = DataTransferRepository.sanitizeFood({
        'id': 'f1',
        'name': 'Ev yapımı köfte',
        'created_at': '2026-01-01T00:00:00Z',
        'last_synced_at': '2026-01-01T00:00:00Z',
        'barcode': '8690504012345',
        'sync_state': 'synced',
        'dietary_fiber_g': 3.2,
        'source': 'barcode',
      });
      for (final banned in <String>[
        'id',
        'created_at',
        'last_synced_at',
        'barcode',
        'sync_state',
        'dietary_fiber_g',
      ]) {
        expect(out.containsKey(banned), isFalse, reason: banned);
      }
      expect(out['name'], 'Ev yapımı köfte');
      expect(out['source'], 'manual');
    });

    test('mealTypeDbValues DB CHECK ile birebir', () {
      expect(DataTransferRepository.mealTypeDbValues,
          {'breakfast', 'lunch', 'dinner', 'snack'});
    });

    test('isDeleted: yumuşak silinmiş yedek satırı canlanmaz', () {
      expect(DataTransferRepository.isDeleted({'deleted_at': '2026-08-15T10:00:00Z'}), isTrue);
      expect(DataTransferRepository.isDeleted(const {}), isFalse);
      expect(DataTransferRepository.isDeleted({'deleted_at': null}), isFalse);
      expect(DataTransferRepository.isDeleted({'deleted_at': ''}), isFalse);
    });
  });

  // =================================================================
  // 7) Bozuk girdi dayanıklılığı
  // =================================================================
  group('bozuk yedek çökmeye yol açmaz', () {
    test('tablo değeri liste değilse atlanır (çökmez)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'meal_entries': 'bu bir liste değil',
        'water_entries': null,
        'weight_entries': 42,
      }));
      expect(report.totalAdded, 0);
    });

    test('satır içi Map değilse atlanır', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'meal_entries': ['metin', 5, null, mealRow(id: 'm1')],
      }));
      expect(report.counts['meal_entries'], 1);
    });

    test('öğünün `entry_date`ı okunamıyorsa ölümcül (nereye yazılacak bilinmiyor)',
        () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await expectLater(
        repo.importBackup('u1', jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'meal_entries': [mealRow(id: 'm1', date: 'değil-tarih')],
        })),
        throwsA(isA<ImportValidationError>()),
      );
      expect(log.postCount, 0);
    });

    test('kilo günü bozuksa ölümcül (kilo trendi bozulur)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      await expectLater(
        repo.importBackup('u1', jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'weight_entries': [
            {'id': 'g1', 'entry_date': 'bilinmiyor', 'weight_kg': 80},
          ],
        })),
        throwsA(isA<ImportValidationError>()),
      );
      expect(log.postCount, 0);
    });

    test('su kaydında `entry_time` yoksa gün başlangıcı türetilir ve SAYILIR',
        () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'water_entries': [
          {'id': 'w1', 'entry_date': '2026-08-15', 'amount_ml': 250},
        ],
      }));
      expect(report.counts['water_entries'], 1);
      expect(report.coerced['water_entries.entry_time'], 1,
          reason: 'saat türetildi — kullanıcı bilgilendirilir');
      final row = log.insertedRows.single.single;
      expect(row['entry_time'], startsWith('2026-08-15T00:00:00'));
      expect(row['entry_date'], '2026-08-15');
    });

    test('besin satırının gıdası yedekte yoksa atlanır (FK ihlali olmaz)', () async {
      final log = CallLog();
      final repo = DataTransferRepository(clientWith(log));
      final report = await repo.importBackup('u1', jsonEncode({
        'version': '1.3.0',
        'exportedAt': 'x',
        'food_nutrition': [
          {'food_id': 'olmayan', 'kcal': 100, 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1},
        ],
      }));
      expect(report.counts['food_nutrition'], 0);
      expect(report.skipped['food_nutrition'], 1);
      expect(log.postCount, 0);
    });
  });
}
