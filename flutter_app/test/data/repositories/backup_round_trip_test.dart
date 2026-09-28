import 'dart:convert';

import 'package:calorix/data/repositories/data_transfer_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// **Uçtan uca** yedek round-trip testi: export → import → ikinci export.
///
/// Bu, yedek/geri yükleme mekaniğinin en değerli testidir çünkü iki
/// istemci (export, import) **ayrı ayrı** geliştirildiği için
/// ayrışabiliyor: `exportData` bir tabloyu yazıyor, `importData` okumuyor
/// → kullanıcı yedeği geri yüklediğinde o tablo **sessizce kayboluyor**.
/// A2r4 bu sınıf hatayı `favorite_foods`/`recent_foods` üzerinde buldu
/// (42 test vardı ama hiçbiri uçtan uca değildi).
///
/// Sahte DB, PostgREST'in gerçek davranışını taklit eder:
///
///  * `POST` gövdesi alınır, `RETURNING id` ile yeni satır numarası
///    üretilir (`gen_random_uuid()` yerine deterministik sayaç — test
///    tekrarlanabilir olsun diye),
///  * `created_at` **yoksa** DB `now()` verir (`NOT NULL DEFAULT now()`
///    → PostgREST `defaultToNull: true` alanı düşürür),
///  * `favorite_foods`/`recent_foods` `UNIQUE(user_id, food_id)` ihlali
///    gerçekte `23505` döner — sahte DB de aynısını yapar (yoksa
///    dedup'un çalıştığı kanıtlanamaz),
///  * `PATCH`/`DELETE` yazma yolları.
http.Response _respond(http.BaseRequest request, Object? body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

/// Tablo → satır listesi. `id` alanı yazma sırasında atanır.
typedef Tables = Map<String, List<Map<String, dynamic>>>;

/// Yedeğin **anlamlı** içeriği — `id` ve `exportedAt` gibi üretilmiş alanlar
/// hariç. İki export karşılaştırılırken `id`'ler farklıdır (yeni satır →
/// yeni UUID) ama kullanıcının verisi aynıdır.
Map<String, dynamic> semanticView(Map<String, dynamic> backup) {
  const generated = {'id', 'exportedAt', 'version'};
  return {
    for (final entry in backup.entries)
      if (!generated.contains(entry.key))
        if (entry.key == 'profile')
          'profile': 'present'
        else
          entry.key: _normalizeRows(entry.value),
  };
}

List<Map<String, dynamic>> _normalizeRows(Object? raw) {
  if (raw is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final r in raw) {
    if (r is! Map) continue;
    out.add(Map<String, dynamic>.from(r)..remove('id'));
  }
  out.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
  return out;
}

/// Sahte Postgres.
///
/// [tables] başlangıç verisidir (kullanıcının mevcut durumu); import
/// sırasında büyür. `GET` sorguları `?select=` listesine ve `?col=eq./in.`
/// filtrelerine **kaba ama yeterli** uyar.
class FakeDb {
  FakeDb(this.tables, {this.userId = 'u1', this.failPostFor = const {}});

  final Tables tables;
  final String userId;

  /// Bu tablolara POST 400 döner (telafi senaryoları).
  final Set<String> failPostFor;

  /// `id` üretim sayacı — `gen_random_uuid()` yerine.
  int _seq = 0;

  /// İstek günlüğü.
  final List<http.Request> requests = <http.Request>[];

  int get postCount => requests.where((r) => r.method == 'POST').length;
  int get getCount => requests.where((r) => r.method == 'GET').length;

  List<http.Request> get posts =>
      requests.where((r) => r.method == 'POST').toList();

  /// `POST /<tablo>` gövdeleri (satır listesi hâlinde çözülmüş).
  List<Map<String, dynamic>> rowsPostedTo(String table) => [
        for (final r in posts)
          if (r.url.path.endsWith(table))
            for (final row in (jsonDecode(r.body) as List))
              (row as Map).cast<String, dynamic>(),
      ];

  /// Bu tabloya yazılan satır sayısı.
  int countWritten(String table) => rowsPostedTo(table).length;

  String _newId() => 'new-${_seq++}';

  SupabaseClient get client => SupabaseClient(
        'https://test.supabase.co',
        'anon-key',
        httpClient: MockClient(_handle),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );

  Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    final table = req.url.path.split('/').last;
    final accept = req.headers['accept'] ?? '';
    final wantObject = accept.contains('pgrst.object');

    if (req.method == 'GET') {
      final rows = _filter(table, req);
      if (wantObject) {
        if (rows.isEmpty) return _respond(req, null);
        return _respond(req, rows.first);
      }
      return _respond(req, rows);
    }

    if (req.method == 'POST') {
      if (failPostFor.contains(table)) {
        return _respond(req, {'code': '23514', 'message': 'check violation'},
            status: 400);
      }
      final decoded = jsonDecode(req.body);
      final incoming = decoded is List
          ? decoded.cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[decoded as Map<String, dynamic>];
      if (incoming.isEmpty) {
        return _respond(req, {'code': 'PGRST102', 'message': 'no rows'},
            status: 400);
      }
      // Anahtar kümesi karşılaştırması **sıralı dize** üzerinden yapılır:
      // `Set<Set<String>>` kimlik eşitliği kullandığı için aynı içerikli iki
      // küme "farklı" sayılır ve her toplu insert hata döner.
      final keysets = incoming.map((r) => (r.keys.toList()..sort()).join('|')).toSet();
      if (keysets.length > 1) {
        return _respond(
            req,
            {'code': 'PGRST102', 'message': 'All object keys must match'},
            status: 400);
      }
      // FK + UNIQUE doğrulaması — gerçek DB davranışı.
      for (final row in incoming) {
        final violation = _validate(table, row);
        if (violation != null) {
          return _respond(req, violation, status: 400);
        }
      }
      final out = <Map<String, dynamic>>[];
      for (final row in incoming) {
        final stored = <String, dynamic>{
          'id': _newId(),
          ...row,
          // Postgres `timestamptz` çıktısı **kendi biçiminde** yazar
          // (`2026-08-03T12:00:00+00:00`); gövdedeki `...Z` dizesi
          // olduğu gibi saklanmaz. Round-trip testleri bu yüzden damgaları
          // **an** olarak karşılaştırır, dize olarak değil.
          for (final c in const [
            'created_at',
            'last_used_at',
            'updated_at',
            'entry_time',
          ])
            if (row[c] != null) c: _pgStamp(row[c]),
          // `created_at` gövdede yoksa DB `now()` verir.
          if (row['created_at'] == null)
            'created_at': '2026-09-28T12:00:00+00:00',
        };
        tables.putIfAbsent(table, () => []).add(stored);
        out.add({'id': stored['id']});
      }
      // `.select(...)` → RETURNING
      return _respond(req, out);
    }

    if (req.method == 'DELETE') {
      final rows = _filter(table, req);
      tables[table] = (tables[table] ?? [])
          .where((r) => !rows.any((d) => d['id'] == r['id']))
          .toList();
      return _respond(req, const <Object>[]);
    }

    if (req.method == 'PATCH') {
      final rows = _filter(table, req);
      if (rows.isEmpty) return _respond(req, const <Object>[]);
      final update = jsonDecode(req.body) as Map<String, dynamic>;
      for (final r in rows) {
        r.addAll(update);
      }
      return _respond(req, rows);
    }

    return _respond(req, const <Object>[]);
  }

  /// NOT NULL + FK + UNIQUE ihlali → PostgREST 400 (`23502`/`23503`/`23505`).
  ///
  /// PostgREST'in `defaultToNull: true` davranışı **yok sayılır**: alan
  /// gövdede `null` ise yazılmamış sayılır ve DB varsayılanı devreye girer
  /// (sözleşme `created_at bozuksa null gönderilir` testinde sabitli).
  Map<String, dynamic>? _validate(String table, Map<String, dynamic> row) {
    const notNull = <String, List<String>>{
      'foods': ['name'],
      'food_nutrition': ['food_id', 'kcal', 'protein_g', 'carbs_g', 'fat_g'],
      'meal_entries': [
        'user_id',
        'entry_date',
        'meal_type',
        'amount_g_ml',
        'calculated_kcal',
        'calculated_protein',
        'calculated_carbs',
        'calculated_fat',
      ],
      'water_entries': ['user_id', 'entry_date', 'amount_ml'],
      'weight_entries': ['user_id', 'entry_date', 'weight_kg'],
      'favorite_foods': ['user_id', 'food_id'],
      'recent_foods': ['user_id', 'food_id'],
      'notification_preferences': ['user_id', 'notification_type'],
    };
    for (final col in notNull[table] ?? const <String>[]) {
      if (row[col] == null) {
        return {'code': '23502', 'message': 'null value in $col'};
      }
    }
    // CHECK kısıtları (DB'de tanımlı — `20260927120000_...:389-402`).
    final checks = <String, bool Function(Map<String, dynamic>)>{
      'meal_entries': (r) {
        final v = (r['amount_g_ml'] as num?)?.toDouble();
        return v == null || (v > 0 && v <= 10000);
      },
      'water_entries': (r) {
        final v = (r['amount_ml'] as num?)?.toInt();
        return v == null || (v > 0 && v <= 10000);
      },
      'weight_entries': (r) {
        final v = (r['weight_kg'] as num?)?.toDouble();
        return v == null || (v > 0 && v <= 1000);
      },
      'notification_preferences': (r) =>
          _clampOk(r['start_hour'], 0, 23) &&
          _clampOk(r['end_hour'], 0, 23) &&
          _clampOk(r['summary_hour'], 0, 23) &&
          _clampOk(r['interval_hours'], 1, 24) &&
          _clampOk(r['summary_day'], 0, 6) &&
          const {
            'weigh_in',
            'daily_log',
            'water',
            'goal_achieved',
            'weekly_summary',
          }.contains(r['notification_type']),
    };
    if (checks[table]?.call(row) == false) {
      return {'code': '23514', 'message': 'check violation'};
    }
    // FK: favorite/recent → foods, notification → unique type
    if (const {'favorite_foods', 'recent_foods'}.contains(table)) {
      final exists =
          (tables['foods'] ?? []).any((f) => f['id'] == row['food_id']);
      if (!exists) {
        return {'code': '23503', 'message': 'foreign key violation'};
      }
      final dup = (tables[table] ?? []).any((f) =>
          f['user_id'] == row['user_id'] && f['food_id'] == row['food_id']);
      if (dup) {
        return {'code': '23505', 'message': 'duplicate key'};
      }
    }
    if (table == 'notification_preferences') {
      final dup = (tables[table] ?? []).any((f) =>
          f['user_id'] == row['user_id'] &&
          f['notification_type'] == row['notification_type']);
      if (dup) {
        return {'code': '23505', 'message': 'duplicate key'};
      }
    }
    return null;
  }

  static bool _clampOk(Object? v, int min, int max) =>
      v == null || (v is num && v >= min && v <= max);

  /// Postgres `timestamptz` çıktı biçimi: `2026-08-03T12:00:00+00:00`.
  ///
  /// Gövdeye `…Z` yazılsın ya da `+00:00`, DB her zaman kendi biçiminde
  /// döner. Bu normalizasyon olmadan round-trip testleri **sahte** bir
  /// asimetri görür (dize farkı, veri farkı değil).
  static String _pgStamp(Object? v) {
    if (v is! String) return '$v';
    final parsed = DateTime.tryParse(v);
    if (parsed == null) return v;
    final u = parsed.toUtc();
    String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
    return '${u.year}-${p(u.month)}-${p(u.day)}T'
        '${p(u.hour)}:${p(u.minute)}:${p(u.second)}+00:00';
  }

  /// `?col=eq.x` / `?col=in.("a","b")` / `?col=is.null` süzgeçleri.
  ///
  /// `foods!inner(name)` embed'i: `favorite_foods.food_id` bir FK olduğu
  /// için `foods.name` filtresi **embed nesnesi** üzerinden eşleşir; sahte
  /// DB `food_id → foods.id` izini çözüp gömülü `{'name': …}` nesnesi
  /// üretir (PostgREST `!inner` join'inin döndürdüğü biçim).
  List<Map<String, dynamic>> _filter(String table, http.Request req) {
    final all = tables[table] ?? const <Map<String, dynamic>>[];
    final q = req.url.queryParameters;
    final select = q['select'] ?? '';
    final embedFoodsName = select.contains('foods!inner(name)');
    final out = <Map<String, dynamic>>[];
    for (final row in all) {
      Map<String, dynamic>? joinedFood;
      var keep = true;
      for (final entry in q.entries) {
        if (const {'select', 'order', 'limit', 'columns'}.contains(entry.key)) {
          continue;
        }
        final v = q[entry.key];
        Object? colValue = row[entry.key];
        if (entry.key == 'foods.name' && embedFoodsName) {
          final matches = (tables['foods'] ?? [])
              .where((f) => f['id'] == row['food_id'])
              .toList();
          if (matches.isEmpty) {
            keep = false;
            break;
          }
          joinedFood = matches.first;
          colValue = joinedFood['name'];
        }
        if (v == 'is.null') {
          keep = keep && colValue == null;
        } else if (v != null && v.startsWith('eq.')) {
          keep = keep && '$colValue' == v.substring(3);
        } else if (v != null && v.startsWith('in.')) {
          final inner = v.substring(3).replaceAll('(', '').replaceAll(')', '');
          final wanted = inner
              .split(',')
              .map((s) => s.replaceAll('"', ''))
              .toSet();
          // `timestamptz` sütunlarında `in` **epoch** üzerinden eşleşir
          // (Postgres `…Z` ile `…+00:00` aynı satırdır; dize karşılaştırması
          // değil). `DataTransferRepository` bu yüzden `_epochMicros` kullanır.
          if (const {'entry_time', 'last_used_at', 'created_at'}
              .contains(entry.key)) {
            final target = _instant(colValue);
            keep = keep &&
                wanted.any((w) => _instant(w) != null && _instant(w) == target);
          } else {
            keep = keep && wanted.contains('$colValue');
          }
        }
      }
      if (!keep) continue;
      out.add(
        joinedFood == null
            ? row
            : <String, dynamic>{...row, 'foods': {'name': joinedFood['name']}},
      );
    }
    return out;
  }
}

/// Gerçekçi "6 aylık aktif kullanıcı" günlük veri seti.
Tables sampleUserData() {
  final meals = <Map<String, dynamic>>[];
  for (var d = 0; d < 30; d++) {
    final day = DateTime.utc(2026, 8, 1 + d).toIso8601String().split('T').first;
    for (var m = 0; m < 3; m++) {
      meals.add({
        'id': 'm-$d-$m',
        'user_id': 'u1',
        'entry_date': day,
        'meal_type': const ['breakfast', 'lunch', 'dinner'][m],
        'food_id': m == 0 ? null : 'f-tavuk',
        'custom_name': m == 0 ? 'Ev yapımı köfte' : null,
        'amount_g_ml': 120.0,
        'calculated_kcal': 520.0,
        'calculated_protein': 32.0,
        'calculated_carbs': 44.0,
        'calculated_fat': 18.0,
        'note': m == 1 ? 'acele' : null,
        'photo_url': m == 2 ? 'https://cdn.example.com/foto.jpg' : null,
        'source': 'manual',
        'created_at': '2026-08-${(1 + d).toString().padLeft(2, '0')}T12:00:00Z',
        'updated_at': '2026-08-${(1 + d).toString().padLeft(2, '0')}T12:00:00Z',
        'deleted_at': null,
      });
    }
  }
  // Yumuşak silinmiş öğün — yedeğe **girmemeli** (`.isFilter`).
  meals.add({
    'id': 'm-deleted',
    'user_id': 'u1',
    'entry_date': '2026-08-10',
    'meal_type': 'snack',
    'custom_name': 'Silinmiş bisküvi',
    'amount_g_ml': 30.0,
    'calculated_kcal': 150.0,
    'calculated_protein': 2.0,
    'calculated_carbs': 20.0,
    'calculated_fat': 6.0,
    'source': 'manual',
    'created_at': '2026-08-10T18:00:00Z',
    'deleted_at': '2026-08-10T19:00:00Z',
  });

  final water = [
    for (var i = 0; i < 40; i++)
      {
        'id': 'w-$i',
        'user_id': 'u1',
        'entry_date': DateTime.utc(2026, 8, 1 + i ~/ 2)
            .toIso8601String()
            .split('T')
            .first,
        'entry_time':
            DateTime.utc(2026, 8, 1 + i ~/ 2, 8 + i % 10, 15, 0)
                .toIso8601String(),
        'amount_ml': 250,
        'created_at': '2026-08-01T08:00:00Z',
        'deleted_at': null,
      },
  ];

  final weights = [
    for (var i = 0; i < 8; i++)
      {
        'id': 'g-$i',
        'user_id': 'u1',
        'entry_date': DateTime.utc(2026, 8, 1 + i * 7)
            .toIso8601String()
            .split('T')
            .first,
        'weight_kg': 80.0 - i * 0.2,
        'note': null,
        'created_at': '2026-08-01T07:00:00Z',
        'deleted_at': null,
      },
  ];

  return {
    'profiles': [
      {
        'id': 'u1',
        'email': 'ayse@example.com',
        'display_name': 'Ayşe',
        'activity_level': 'very_active',
        'daily_calorie_target': 2200.0,
      }
    ],
    'meal_entries': meals,
    'water_entries': water,
    'weight_entries': weights,
    'foods': [
      {
        'id': 'f-tavuk',
        'name': 'Tavuk Göğüsü',
        'brand': 'Market',
        'serving_size_g': 100.0,
        'serving_description': 'porsiyon',
        'source': 'manual',
        'image_url': null,
        'popularity_count': 12,
        'verified': false,
        'created_by': 'u1',
        'created_at': '2026-01-05T10:00:00Z',
        'updated_at': '2026-01-05T10:00:00Z',
      },
      {
        'id': 'f-kofte',
        'name': 'Ev yapımı köfte',
        'brand': null,
        'serving_size_g': 100.0,
        'source': 'manual',
        'popularity_count': 3,
        'verified': false,
        'created_by': 'u1',
        'created_at': '2026-01-07T10:00:00Z',
        'updated_at': '2026-01-07T10:00:00Z',
      },
    ],
    'food_nutrition': [
      {
        'id': 'n-1',
        'food_id': 'f-tavuk',
        'per_100_g_ml': true,
        'kcal': 165.0,
        'protein_g': 31.0,
        'carbs_g': 0.0,
        'fat_g': 3.6,
        'fiber_g': 0.0,
        'sugar_g': 0.0,
        'salt_g': 0.1,
        'saturated_fat_g': 1.0,
        'trans_fat_g': null,
        'nova_score': 1,
        'nutri_score': 'A',
        'created_at': '2026-01-05T10:00:00Z',
        'updated_at': '2026-01-05T10:00:00Z',
      },
      {
        'id': 'n-2',
        'food_id': 'f-kofte',
        'per_100_g_ml': true,
        'kcal': 240.0,
        'protein_g': 18.0,
        'carbs_g': 2.0,
        'fat_g': 16.0,
        'fiber_g': null,
        'sugar_g': null,
        'salt_g': 0.8,
        'saturated_fat_g': 6.0,
        'trans_fat_g': null,
        'nova_score': null,
        'nutri_score': null,
        'created_at': '2026-01-07T10:00:00Z',
        'updated_at': '2026-01-07T10:00:00Z',
      },
    ],
    'favorite_foods': [
      {'id': 'ff-1', 'user_id': 'u1', 'food_id': 'f-tavuk', 'created_at': '2026-02-01T10:00:00Z'},
      {'id': 'ff-2', 'user_id': 'u1', 'food_id': 'f-kofte', 'created_at': '2026-02-02T10:00:00Z'},
    ],
    'recent_foods': [
      {
        'id': 'rf-1',
        'user_id': 'u1',
        'food_id': 'f-tavuk',
        'last_used_at': '2026-08-20T10:00:00Z',
        'use_count': 7,
      },
      {
        'id': 'rf-2',
        'user_id': 'u1',
        'food_id': 'f-kofte',
        'last_used_at': '2026-08-19T10:00:00Z',
        'use_count': 2,
      },
    ],
    'notification_preferences': [
      {
        'id': 'np-1',
        'user_id': 'u1',
        'notification_type': 'daily_log',
        'push_enabled': true,
        'email_enabled': false,
        'start_hour': 8,
        'end_hour': 22,
        'interval_hours': 4,
        'summary_day': 1,
        'summary_hour': 9,
        'created_at': '2026-01-01T10:00:00Z',
        'updated_at': '2026-01-01T10:00:00Z',
      },
    ],
  };
}

void main() {
  group('yedek round-trip: export → import → export', () {
    test('günlük veri seti ikinci export\'ta **aynı** (kayıt sayıları eşit)', () async {
      final db = FakeDb(sampleUserData());
      final repo = DataTransferRepository(db.client);

      // 1) Dışa aktar.
      final first = jsonDecode(await repo.exportData('u1')) as Map<String, dynamic>;
      expect((first['meal_entries'] as List), hasLength(90));
      expect((first['water_entries'] as List), hasLength(40));
      expect((first['weight_entries'] as List), hasLength(8));
      expect((first['foods'] as List), hasLength(2));
      expect((first['food_nutrition'] as List), hasLength(2));
      expect((first['favorite_foods'] as List), hasLength(2));
      expect((first['recent_foods'] as List), hasLength(2));
      expect((first['notification_preferences'] as List), hasLength(1));

      // 2) Boş hesaba geri yükle (yedek farklı bir cihazın hesabına).
      final empty = FakeDb(<String, List<Map<String, dynamic>>>{});
      final target = DataTransferRepository(empty.client);
      final report = await target.importBackup('yeni-kullanici', jsonEncode(first));

      expect(report.failedStage, isNull);
      expect(report.rolledBack, isNull);
      expect(report.counts['meal_entries'], 90);
      expect(report.counts['water_entries'], 40);
      expect(report.counts['weight_entries'], 8);
      expect(report.counts['foods'], 2);
      expect(report.counts['food_nutrition'], 2);
      // Görev 1: favoriler ve son kullanılanlar geri geliyor mu?
      expect(report.counts['favorite_foods'], 2);
      expect(report.counts['recent_foods'], 2);
      expect(report.counts['notification_preferences'], 1);

      // 3) İkinci dışa aktarım ve karşılaştırma.
      final second =
          jsonDecode(await target.exportData('yeni-kullanici')) as Map<String, dynamic>;
      final a = semanticView(first);
      final b = semanticView(second);
      for (final table in DataTransferRepository.importTables) {
        expect((b[table] as List).length, (a[table] as List).length,
            reason: '$table satır sayısı round-trip\'te değişti');
      }
    });

    test('içerik eşitliği: ölçülebilir alanlar ve favoriler birebir aynı', () async {
      final first = jsonDecode(
              await DataTransferRepository(FakeDb(sampleUserData()).client).exportData('u1'))
          as Map<String, dynamic>;

      final empty = FakeDb(<String, List<Map<String, dynamic>>>{});
      final target = DataTransferRepository(empty.client);
      await target.importBackup('yeni-kullanici', jsonEncode(first));
      final second =
          jsonDecode(await target.exportData('yeni-kullanici')) as Map<String, dynamic>;

      // Öğünler: DB'ye yazılabilir ölçülebilir alanlar birebir.
      // Sıralama `entry_date|meal_type|custom_name` üzerinden — bu üçü
      // `DataTransferRepository`'nin dedup anahtarıdır, yani satır
      // eşleşmesi **kanonik** (aynı anahtar = aynı kayıt).
      final m1 = _sorted(first['meal_entries'],
          by: const ['entry_date', 'meal_type', 'custom_name']);
      final m2 = _sorted(second['meal_entries'],
          by: const ['entry_date', 'meal_type', 'custom_name']);
      expect(m2, hasLength(m1.length));
      for (var i = 0; i < m1.length; i++) {
        for (final col in const [
          'entry_date',
          'meal_type',
          'custom_name',
          'amount_g_ml',
          'calculated_kcal',
          'calculated_protein',
          'calculated_carbs',
          'calculated_fat',
          'note',
          'photo_url',
          'source',
        ]) {
          expect(m2[i][col], m1[i][col], reason: 'öğün alanı $col (satır $i)');
        }
        // `created_at` **an** olarak korunur (dize biçimi DB'ye bağlı:
        // `…Z` → `…+00:00`; aynı an, farklı yazım).
        expect(_instant(m2[i]['created_at']), _instant(m1[i]['created_at']),
            reason: 'öğün created_at (satır $i)');
      }

      // Su kayıtları — dedup anahtarı `entry_time` (epoch).
      final w1 = _sorted(first['water_entries'], by: const ['entry_time']);
      final w2 = _sorted(second['water_entries'], by: const ['entry_time']);
      expect(w2, hasLength(w1.length));
      for (var i = 0; i < w1.length; i++) {
        expect(_instant(w2[i]['entry_time']), _instant(w1[i]['entry_time']));
        expect(w2[i]['entry_date'], w1[i]['entry_date']);
        expect(w2[i]['amount_ml'], w1[i]['amount_ml']);
      }

      // Kilo kayıtları — dedup anahtarı `entry_date`.
      final g1 = _sorted(first['weight_entries'], by: const ['entry_date']);
      final g2 = _sorted(second['weight_entries'], by: const ['entry_date']);
      expect(g2, hasLength(g1.length));
      for (var i = 0; i < g1.length; i++) {
        expect(g2[i]['entry_date'], g1[i]['entry_date']);
        expect((g2[i]['weight_kg'] as num).toDouble(),
            (g1[i]['weight_kg'] as num).toDouble());
      }

      // Besin satırları — içerik eşitliği (`food_id` değişir, değerler değil).
      // Satırlar **gıda adı** üzerinden eşleşir: `food_nutrition` gövdesinde
      // `kcal` sayı olarak yazılır ama import `_requireNum` ile **dize**
      // (`"165.0"`) üretir, bu yüzden **küme** karşılaştırması kullanılır
      // (JSON sıralaması yazım biçimine göre sıra değiştirir).
      final names1 = _namesById(first);
      final names2 = _namesById(second);
      final nut1 = _nutritionByFood(first, names1);
      final nut2 = _nutritionByFood(second, names2);
      expect(nut2.keys.toSet(), nut1.keys.toSet());
      for (final name in nut1.keys) {
        for (final col in const [
          'kcal',
          'protein_g',
          'carbs_g',
          'fat_g',
          'fiber_g',
          'sugar_g',
          'salt_g',
          'saturated_fat_g',
          'trans_fat_g',
          'nova_score',
          'nutri_score',
          'per_100_g_ml',
        ]) {
          expect(_numEq(nut2[name]![col], nut1[name]![col]),
              isTrue,
              reason: 'besin alanı $col ($name): '
                  '${nut1[name]![col]} → ${nut2[name]![col]}');
        }
      }

      // Favoriler: gıda **adları** eşitliği (`food_id` yeni UUID alır).
      final favNames1 = _favoriteNames(first);
      final favNames2 = _favoriteNames(second);
      expect(favNames2, favNames1);
      expect(favNames2, {'Tavuk Göğüsü', 'Ev yapımı köfte'});

      // Son kullanılanlar: ad + `use_count` + `last_used_at` eşitliği.
      final rec1 = _recentView(first);
      final rec2 = _recentView(second);
      expect(rec2, rec1);
      expect(rec2['Tavuk Göğüsü']?['use_count'], 7);
      expect(rec2['Ev yapımı köfte']?['use_count'], 2);

      // Bildirim tercihleri.
      final p1 = first['notification_preferences'] as List;
      final p2 = second['notification_preferences'] as List;
      expect(p2, hasLength(1));
      for (final col in const [
        'notification_type',
        'push_enabled',
        'email_enabled',
        'start_hour',
        'end_hour',
        'interval_hours',
        'summary_day',
        'summary_hour',
      ]) {
        expect((p2.single as Map)[col], (p1.single as Map)[col],
            reason: 'bildirim alanı $col');
      }
    });

    test('yumuşak silinmiş kayıt round-trip\'te **canlanmaz**', () async {
      final first = jsonDecode(
              await DataTransferRepository(FakeDb(sampleUserData()).client).exportData('u1'))
          as Map<String, dynamic>;
      for (final table in const ['meal_entries', 'water_entries', 'weight_entries']) {
        for (final row in (first[table] as List).cast<Map<String, dynamic>>()) {
          expect(row['deleted_at'], isNull, reason: '$table yumuşak silinmiş satır içeriyor');
        }
      }
      expect(
        (first['meal_entries'] as List)
            .cast<Map<String, dynamic>>()
            .any((m) => m['custom_name'] == 'Silinmiş bisküvi'),
        isFalse,
      );

      final empty = FakeDb(<String, List<Map<String, dynamic>>>{});
      final target = DataTransferRepository(empty.client);
      final report = await target.importBackup('u', jsonEncode(first));
      final second =
          jsonDecode(await target.exportData('u')) as Map<String, dynamic>;
      expect((second['meal_entries'] as List), hasLength(report.counts['meal_entries']));
      expect(
        (second['meal_entries'] as List)
            .cast<Map<String, dynamic>>()
            .any((m) => m['custom_name'] == 'Silinmiş bisküvi'),
        isFalse,
        reason: 'yumuşak silinmiş öğün yeni id ile geri gelmemeli',
      );
    });

    test('aynı hesaba **ikinci kez** import: hiçbir kayıt çoğalmaz (idempotent)', () async {
      final first = jsonDecode(
              await DataTransferRepository(FakeDb(sampleUserData()).client).exportData('u1'))
          as Map<String, dynamic>;

      final target = FakeDb(<String, List<Map<String, dynamic>>>{});
      final repo = DataTransferRepository(target.client);
      await repo.importBackup('u1', jsonEncode(first));
      final before = {
        for (final t in DataTransferRepository.importTables)
          t: (target.tables[t] ?? []).length,
      };

      // Aynı yedek **aynı kullanıcıya** tekrar yükleniyor (kullanıcı iki
      // kez "geri yükle"ye basmış).
      final again = await repo.importBackup('u1', jsonEncode(first));
      for (final t in DataTransferRepository.importTables) {
        expect(again.counts[t], 0, reason: '$t yeniden yazıldı (dedup kırık)');
      }
      for (final entry in before.entries) {
        expect((target.tables[entry.key] ?? []).length, entry.value,
            reason: '${entry.key} satır sayısı değişti');
      }
    });
  });

  group('simetrik olmayan (round-trip kaybı yaratan) senaryolar', () {
    test('`created_at` round-trip: import damgasını korur, kayıp yaşanmaz', () async {
      // `foods.created_at` beyaz listede **yok** (A2r4 kararı: kullanıcı/
      // denetim alanı kopyalanmaz) → gıda yeni `now()` alır. Bu bilinçli
      // bir asimetridir; kullanıcının verisini etkilemez ama güncelleme
      // sırasını etkileyebilir. Test, **günlük kayıtların** damgasının
      // korunduğunu ve gıda damgalarının kaybolduğunu açıkça belgeler.
      final first = jsonDecode(
              await DataTransferRepository(FakeDb(sampleUserData()).client).exportData('u1'))
          as Map<String, dynamic>;
      final foodStamp = (first['foods'] as List).cast<Map<String, dynamic>>().first['created_at'];

      final empty = FakeDb(<String, List<Map<String, dynamic>>>{});
      final target = DataTransferRepository(empty.client);
      await target.importBackup('u', jsonEncode(first));
      final second = jsonDecode(await target.exportData('u')) as Map<String, dynamic>;

      // Öğün/su/kilo damgaları korunur (created_at taşınır).
      final m1 = _sorted(first['meal_entries'],
          by: const ['entry_date', 'meal_type', 'custom_name']);
      final m2 = _sorted(second['meal_entries'],
          by: const ['entry_date', 'meal_type', 'custom_name']);
      expect(
        m1.map((r) => _instant(r['created_at'])).toSet(),
        m2.map((r) => _instant(r['created_at'])).toSet(),
        reason: 'günlük kayıtlarda created_at round-trip kaybı',
      );

      // Gıda damgaları **yeniden yazılır** — belgelenmiş asimetri.
      final foodStamp2 =
          (second['foods'] as List).cast<Map<String, dynamic>>().first['created_at'];
      expect(foodStamp2, isNotNull);
      expect(_instant(foodStamp2), isNot(_instant(foodStamp)),
          reason: 'bu test bir kez değişirse importTables beyaz listesi değişmiştir');
    });

    test('`exportedAt`/`version` üretilmiş alanlardır (karşılaştırmaya girmez)', () {
      final view = semanticView(
          {'version': '1.3.0', 'exportedAt': 'x', 'foods': <Object>[]});
      expect(view.containsKey('version'), isFalse);
      expect(view.containsKey('exportedAt'), isFalse);
      expect(view.containsKey('foods'), isTrue);
    });

    test('`nova_score` geçersizse **NULL** yazılır, sayaç değeri DEĞİL', () async {
      // REGRESYON (Tur 5, uçtan uca test buldu): eski kod
      // `_count(coerced, 'food_nutrition.nova_score')` yazıyordu ve
      // `_count` **sayacın değerini** döndürdü → sınıflandırılmamış bir
      // gıda `nova_score = 1` ("işlenmemiş") olarak kaydediliyordu.
      // 42 mevcut test yalnızca `coerced` sayacını doğruluyordu.
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'A'},
            {'id': 'f2', 'name': 'B'},
            {'id': 'f3', 'name': 'C'},
          ],
          'food_nutrition': [
            // 1) aralık dışı (10) → sayılır, NULL yazılır
            {'food_id': 'f1', 'kcal': 1, 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1, 'nova_score': 10},
            // 2) negatif → `_positiveNum` eler, NULL yazılır, **sayılmaz**
            //    (veri "yok" sayılır, "bozuk" sayılmaz)
            {'food_id': 'f2', 'kcal': 1, 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1, 'nova_score': -1},
            // 3) eksik → NULL, sayılmaz
            {'food_id': 'f3', 'kcal': 1, 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1},
          ],
        }),
      );
      final scores = db
          .rowsPostedTo('food_nutrition')
          .map((r) => r['nova_score'])
          .toList();
      expect(scores, everyElement(isNull),
          reason: 'geçersiz/eksik NOVA sınıfı uydurulmamalı, NULL olmalı: $scores');
      // Yalnızca **aralık dışı pozitif** değer (10) sayılır; negatif ve eksik
      // değer `_positiveNum` öncesinde elenir ve sayaç artmaz.
      expect(report.coerced['food_nutrition.nova_score'], 1);
    });

    test('geçerli `nova_score` korunur (1..4 sınıflandırması bozulmaz)', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            for (var i = 1; i <= 4; i++) {'id': 'f$i', 'name': 'G$i'},
          ],
          'food_nutrition': [
            for (var i = 1; i <= 4; i++)
              {'food_id': 'f$i', 'kcal': 1, 'protein_g': 1, 'carbs_g': 1, 'fat_g': 1, 'nova_score': i},
          ],
        }),
      );
      expect(
        db.rowsPostedTo('food_nutrition').map((r) => r['nova_score']).toList()..sort(),
        [1, 2, 3, 4],
      );
    });
  });

  group('favoriler/son kullanılanlar: içe aktarım sözleşmesi', () {
    test('`user_id` HER kayıtta yazılır (RLS `WITH CHECK (auth.uid()=user_id)`)', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'oturumdaki-kullanici',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'Tavuk'},
          ],
          'favorite_foods': [
            // Yedeğin `user_id`'si **başka bir kullanıcıya** ait olabilir
            // (başka cihazdan alınan yedek).
            {'id': 'ff1', 'user_id': 'başka-kullanici', 'food_id': 'f1'},
          ],
          'recent_foods': [
            {'id': 'rf1', 'user_id': 'başka-kullanici', 'food_id': 'f1'},
          ],
        }),
      );

      expect(report.counts['favorite_foods'], 1);
      expect(report.counts['recent_foods'], 1);
      for (final table in const ['favorite_foods', 'recent_foods']) {
        final rows = db.rowsPostedTo(table);
        expect(rows, hasLength(1));
        expect(rows.single['user_id'], 'oturumdaki-kullanici',
            reason: '$table: yedeğin user_id\'si yazıldı → RLS reddeder');
      }
    });

    test('`food_id` yedekteki eski UUID değil, yeni gıda id\'sidir', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'eski-id', 'name': 'Tavuk'},
          ],
          'favorite_foods': [
            {'id': 'ff1', 'food_id': 'eski-id'},
          ],
          'recent_foods': [
            {'id': 'rf1', 'food_id': 'eski-id'},
          ],
        }),
      );
      // Sahte DB FK kontrolü yapıyor: `food_id` gerçekten `foods` tablosundaki
      // yeni satırın id'si olmalı (yoksa 23503 dönerdi).
      final foods = db.tables['foods']!;
      expect(foods, hasLength(1));
      final newId = foods.single['id'];
      expect(db.rowsPostedTo('favorite_foods').single['food_id'], newId);
      expect(db.rowsPostedTo('recent_foods').single['food_id'], newId);
      expect(newId, isNot('eski-id'));
    });

    test('gıdası yedekte yoksa favori **atlanır ve raporlanır** (ölümcül değil)', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'Tavuk'},
          ],
          'food_nutrition': [
            {'food_id': 'f1', 'kcal': 165, 'protein_g': 31, 'carbs_g': 0, 'fat_g': 3.6},
          ],
          'meal_entries': [
            {
              'id': 'm1',
              'entry_date': '2026-08-15',
              'meal_type': 'lunch',
              'amount_g_ml': 100,
              'calculated_kcal': 165,
              'calculated_protein': 31,
              'calculated_carbs': 0,
              'calculated_fat': 3.6,
            },
          ],
          'favorite_foods': [
            {'id': 'ff-var', 'food_id': 'olmayan-gida'},
            {'id': 'ff-ok', 'food_id': 'f1'},
          ],
        }),
      );

      // Ölümcül olsaydı tüm yedek geri yüklenemezdi — oysa günlük tam.
      expect(report.counts['meal_entries'], 1);
      expect(report.counts['foods'], 1);
      expect(report.counts['favorite_foods'], 1, reason: 'yalnız eşleşen favori');
      expect(report.skipped['favorite_foods'], 1);
      final issue = report.issues.firstWhere((i) => i.table == 'favorite_foods');
      expect(issue.field, 'food_id');
      expect(issue.isFatal, isFalse);
      // Kullanıcı bilgilendirilir (sessiz veri kaybı yok).
      expect(report.toString(), contains('favorite_foods'));
    });

    test('aynı gıda ikinci favori atlanır (UNIQUE user_id+food_id)', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'Tavuk'},
          ],
          'favorite_foods': [
            {'id': 'ff1', 'food_id': 'f1'},
            {'id': 'ff2', 'food_id': 'f1'},
          ],
          'recent_foods': [
            {'id': 'rf1', 'food_id': 'f1'},
            {'id': 'rf2', 'food_id': 'f1'},
          ],
        }),
      );
      // 23505 duplicate key tüm import'u düşürürdü.
      expect(report.counts['favorite_foods'], 1);
      expect(report.counts['recent_foods'], 1);
      expect(report.skipped['favorite_foods'], 1);
      expect(report.skipped['recent_foods'], 1);
    });

    test('DB\'de zaten favorilenen gıda tekrar yazılmaz (23505 koruması)', () async {
      final db = FakeDb({
        'foods': [
          {'id': 'mevcut-gida', 'name': 'Tavuk', 'created_by': 'u1'},
        ],
        'favorite_foods': [
          {'id': 'ff-var', 'user_id': 'u1', 'food_id': 'mevcut-gida'},
        ],
      });
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'Tavuk'},
          ],
          'favorite_foods': [
            {'id': 'ff1', 'food_id': 'f1'},
          ],
        }),
      );
      expect(report.counts['favorite_foods'], 0);
      expect(db.rowsPostedTo('favorite_foods'), isEmpty);
      // Varlık kontrolü `foods!inner(name)` embed'iyle yapıldı.
      final favGet = db.requests
          .where((r) => r.method == 'GET' && r.url.path.endsWith('favorite_foods'))
          .toList();
      expect(favGet, isNotEmpty, reason: 'favori varlığı sorgulanmadı');
      expect(favGet.first.url.queryParameters['select'], contains('foods!inner'));
      expect(favGet.first.url.queryParameters['user_id'], 'eq.u1');
    });

    test('`recent_foods.use_count` ve `last_used_at` korunur', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'Tavuk'},
          ],
          'recent_foods': [
            {
              'id': 'rf1',
              'food_id': 'f1',
              'last_used_at': '2026-08-20T10:00:00.000Z',
              'use_count': 9,
            },
          ],
        }),
      );
      final row = db.rowsPostedTo('recent_foods').single;
      expect(row['use_count'], 9);
      expect(DateTime.parse(row['last_used_at'] as String).toUtc(),
          DateTime.utc(2026, 8, 20, 10));
    });

    test('geçersiz `use_count` DB aralığına çekilir ve SAYILIR', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'Tavuk'},
            {'id': 'f2', 'name': 'Pilav'},
          ],
          'recent_foods': [
            {'id': 'rf1', 'food_id': 'f1', 'use_count': -3},
            {'id': 'rf2', 'food_id': 'f2', 'use_count': 'çok'},
            {'id': 'rf3', 'food_id': 'f2', 'use_count': 4},
          ],
        }),
      );
      // `f2` için ikinci kayıt (rf3) UNIQUE nedeniyle atlanır; rf2 yazılır.
      final values = db.rowsPostedTo('recent_foods').map((r) => r['use_count']).toList();
      expect(values, containsAll(<int>[1]));
      expect(report.coerced['recent_foods.use_count'], 2);
      expect(report.counts['recent_foods'], 2);
    });

    test('`recent_foods` tablosu favorilerle **aynı gıdayı** ayrı satırda tutar', () async {
      // İki tablo farklı UNIQUE kısıtlarına sahip; birini yazmak diğerini
      // engellemez. (Sahte DB'de ikisinin de yazıldığı kanıtlanır.)
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'foods': [
            {'id': 'f1', 'name': 'Tavuk'},
          ],
          'favorite_foods': [
            {'id': 'ff1', 'food_id': 'f1'},
          ],
          'recent_foods': [
            {'id': 'rf1', 'food_id': 'f1'},
          ],
        }),
      );
      expect(report.counts['favorite_foods'], 1);
      expect(report.counts['recent_foods'], 1);
    });
  });

  group('bildirim tercihleri: içe aktarım sözleşmesi', () {
    test('geçerli tercih yazılır, `user_id` oturumdan gelir', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'oturumdaki',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'notification_preferences': [
            {
              'id': 'np1',
              'user_id': 'başka',
              'notification_type': 'water',
              'push_enabled': false,
              'start_hour': 7,
              'end_hour': 20,
              'interval_hours': 2,
              'summary_day': 0,
              'summary_hour': 8,
            },
          ],
        }),
      );
      expect(report.counts['notification_preferences'], 1);
      final row = db.rowsPostedTo('notification_preferences').single;
      expect(row['user_id'], 'oturumdaki');
      expect(row['notification_type'], 'water');
      expect(row['push_enabled'], isFalse);
      expect(row['email_enabled'], isTrue, reason: 'eksik alan DB varsayılanı');
    });

    test('CHECK dışı bildirim türü atlanır (tüm import\'u düşürmez)', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'meal_entries': [
            {
              'entry_date': '2026-08-15',
              'meal_type': 'lunch',
              'amount_g_ml': 100,
              'calculated_kcal': 100,
              'calculated_protein': 1,
              'calculated_carbs': 1,
              'calculated_fat': 1,
            },
          ],
          'notification_preferences': [
            {'id': 'np1', 'notification_type': 'gece_yarisi_hatirlatmasi'},
            {'id': 'np2', 'notification_type': 'weigh_in'},
          ],
        }),
      );
      expect(report.counts['meal_entries'], 1);
      expect(report.counts['notification_preferences'], 1);
      expect(report.skipped['notification_preferences'], 1);
    });

    test('saat/ara değerleri DB aralığına çekilir ve SAYILIR', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'notification_preferences': [
            {
              'id': 'np1',
              'notification_type': 'daily_log',
              'start_hour': 99,
              'end_hour': -4,
              'interval_hours': 0,
              'summary_day': 9,
              'summary_hour': 'dokuz',
            },
          ],
        }),
      );
      // CHECK ihlali (23514) tüm import'u düşürürdü.
      expect(report.counts['notification_preferences'], 1);
      final row = db.rowsPostedTo('notification_preferences').single;
      expect(row['start_hour'], 9);
      expect(row['end_hour'], 21);
      expect(row['interval_hours'], 3);
      expect(row['summary_day'], 1);
      expect(row['summary_hour'], 9);
      expect(report.coerced['notification_preferences.start_hour'], 1);
      expect(report.coerced['notification_preferences.summary_hour'], 1);
    });

    test('aynı tür için ikinci tercih atlanır (UNIQUE user_id+type)', () async {
      final db = FakeDb(<String, List<Map<String, dynamic>>>{});
      final report = await DataTransferRepository(db.client).importBackup(
        'u1',
        jsonEncode({
          'version': '1.3.0',
          'exportedAt': 'x',
          'notification_preferences': [
            {'id': 'np1', 'notification_type': 'water'},
            {'id': 'np2', 'notification_type': 'water'},
          ],
        }),
      );
      expect(report.counts['notification_preferences'], 1);
      expect(report.skipped['notification_preferences'], 1);
    });
  });

  group('telafi (rollback) yeni tabloları da kapsar', () {
    test('`notification_preferences` yazımı 400 → önceki tablolar telafi edilir', () async {
      final db = FakeDb(
        <String, List<Map<String, dynamic>>>{},
        failPostFor: {'notification_preferences'},
      );

      try {
        await DataTransferRepository(db.client).importBackup(
          'u1',
          jsonEncode({
            'version': '1.3.0',
            'exportedAt': 'x',
            'foods': [
              {'id': 'f1', 'name': 'Tavuk'},
            ],
            'favorite_foods': [
              {'id': 'ff1', 'food_id': 'f1'},
            ],
            'recent_foods': [
              {'id': 'rf1', 'food_id': 'f1'},
            ],
            'notification_preferences': [
              {'id': 'np1', 'notification_type': 'water'},
            ],
          }),
        );
        fail('yazma hatası fırlatmalıydı');
      } on ImportWriteError catch (e) {
        expect(e.stage, 'notification_preferences');
        expect(e.report.rolledBack, isTrue);
        // Hiçbir kayıt kalmaz — kullanıcının verisi tutarlı.
        expect(e.report.counts['foods'], 0);
        expect(e.report.counts['favorite_foods'], 0);
        expect(e.report.counts['recent_foods'], 0);
        expect(e.report.writtenTables, isEmpty);
      }
      // Telafi DELETE'leri yeni tabloları da kapsar.
      final deletes = db.requests.where((r) => r.method == 'DELETE');
      for (final t in const ['foods', 'favorite_foods', 'recent_foods']) {
        expect(deletes.any((r) => r.url.path.endsWith(t)), isTrue,
            reason: '$t telafi edilmedi');
      }
      // Sıra: bağımlılık sırasının tersi (favoriler `foods`'tan önce).
      final deleteOrder = deletes
          .map((r) => r.url.path.split('/').last)
          .toList();
      expect(
        deleteOrder.indexOf('favorite_foods') < deleteOrder.indexOf('foods'),
        isTrue,
        reason: 'favoriler gıdalardan önce silinmeli ($deleteOrder)',
      );
    });
  });
}

/// Satırları **anlamlı alanlarla** sıralar.
///
/// `id` sıralaması kullanılamaz: import sonrası id'ler **değişir** (yeni
/// UUID). JSON dize sıralaması da kullanılamaz: `created_at` yazım biçimi
/// `…Z` ↔ `…+00:00` olduğu için sıra iki export arasında kayabilir ve
/// karşılaştırma **yanlış satırı** karşılaştırır.
List<Map<String, dynamic>> _sorted(Object? raw, {List<String> by = const []}) {
  final out = (raw as List).cast<Map<String, dynamic>>().toList();
  if (by.isEmpty) {
    out.sort((a, b) => _canonical(a).compareTo(_canonical(b)));
    return out;
  }
  out.sort((a, b) {
    for (final k in by) {
      final c = '${a[k]}'.compareTo('${b[k]}');
      if (c != 0) return c;
    }
    return 0;
  });
  return out;
}

/// `id` hariç, damgaları **an** olarak yazan kanonik JSON.
String _canonical(Map<String, dynamic> row) {
  final m = <String, dynamic>{};
  for (final e in row.entries) {
    if (e.key == 'id') continue;
    final v = e.value;
    if (v is String) {
      final d = DateTime.tryParse(v);
      m[e.key] = d == null ? v : d.toUtc().toIso8601String();
    } else {
      m[e.key] = v;
    }
  }
  return jsonEncode(m);
}

/// Damgayı **an** olarak normalize eder (Postgres `…Z` ↔ `…+00:00`
/// yazım farkı veri farkı değildir).
DateTime? _instant(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

/// Yedeğin `foods` adlarıyla eşlenmiş favori **adları**.
Set<String> _favoriteNames(Map<String, dynamic> backup) {
  final names = _namesById(backup);
  return (backup['favorite_foods'] as List)
      .cast<Map<String, dynamic>>()
      .map((r) => names[r['food_id']])
      .whereType<String>()
      .toSet();
}

/// `food_id` → gıda adı (yedeğin kendi `foods` listesinden).
Map<String, String> _namesById(Map<String, dynamic> backup) => {
      for (final f in (backup['foods'] as List).cast<Map<String, dynamic>>())
        '${f['id']}': '${f['name']}',
    };

/// Gıda adı → besin satırı (yedekteki `food_nutrition` listesinden).
Map<String, Map<String, dynamic>> _nutritionByFood(
  Map<String, dynamic> backup,
  Map<String, String> namesById,
) =>
    {
      for (final n in (backup['food_nutrition'] as List).cast<Map<String, dynamic>>())
        if (namesById['${n['food_id']}'] != null)
          namesById['${n['food_id']}']!: n,
    };

/// Sayısal alan karşılaştırması.
///
/// Postgres `NUMERIC` **sayı** döner; import `_requireNum` dize yazdığı
/// için dönüş değeri `"165.0"` olur. İkisi aynı sayıdır — karşılaştırma
/// `double` üzerinden yapılır (`null` yalnızca `null` ile eşleşir).
bool _numEq(Object? a, Object? b) {
  if (a == null || b == null) return a == null && b == null;
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  final x = num.tryParse('$a');
  final y = num.tryParse('$b');
  if (x == null || y == null) return '$a' == '$b';
  return x.toDouble() == y.toDouble();
}

Map<String, dynamic> _recentView(Map<String, dynamic> backup) {
  final names = _namesById(backup);
  final out = <String, dynamic>{};
  for (final r in (backup['recent_foods'] as List).cast<Map<String, dynamic>>()) {
    final name = names[r['food_id']];
    if (name == null) continue;
    out[name] = {
      'use_count': r['use_count'],
      'last_used_at': r['last_used_at'] == null
          ? null
          : DateTime.parse(r['last_used_at'] as String).toUtc().toIso8601String(),
    };
  }
  return out;
}
