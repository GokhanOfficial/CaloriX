import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';

/// Web `useDataExport.ts` karşılığı — tüm kullanıcı verilerini JSON olarak
/// dışa aktarır ve yedekten içe aktarır (yalnızca eklemeli, dedup'lı).
///
/// DB kapalıyken bu fonksiyonlar canlı veriye dokunmaz; birim mantığı
/// (dedup, şema) web ile birebir aynıdır.
class DataTransferRepository {
  DataTransferRepository(this._client);

  final SupabaseClient _client;

  /// `inFilter` değerleri **sorgu dizesine** gömülür (`?col=in.("a","b")`).
  ///
  /// PostgREST'in önerilen pratik URL tavanı ~8 KB'dir; bunu aşan bir
  /// `in` listesi **414 URI Too Long** ile reddedilir (bazı reverse proxy'lerde
  /// 400/431). Ters proxy olmayan `supabase.co` uçlarındaki `max-rows`/güneven
  /// katmanlarında ise bağlantı "Header or Cookie too large" olarak kopar.
  ///
  /// Aşılması matematiksel olarak kaçınk değil: `_cleanFilterArray` (postgrest
  /// 2.9.1, `postgrest_builder.dart:635`) **dize değerlerini çift tırnakla
  /// sarar** → 36 haneli bir UUID + 2 tırnak + virgül = 39 bayt. 8 KB'de
  /// 210 kayıt; 5000 `entry_time` dedup'i 195 KB'lık bir tek sorgu demek.
  ///
  /// 100 güvenli: en kötü kayıt ~60 bayt → ~6 KB. `uuidGenerateV4` 2000'lik
  /// yedekte URL sınırının **%48'i**; 5000'lik yedekte tek parça zaten
  /// 414 alırdı. Daha küçük dilimler yalnızca daha çok istek demek.
  static const int inFilterChunkSize = 100;

  /// `meal_type` DB değerleri — PostgreSQL `meal_type` ENUM ve DB CHECK
  /// kısıtı (migration `20260111041204_...sql:11`, `full_setup.sql:23`).
  ///
  /// Yedek içe aktarımında geçersiz bir `meal_type` insert'i CHECK ihlaliyle
  /// 400 döndürür ve **tüm içe aktarma** orada durur; [sanitizeMealEntry]
  /// bu listeyi kullanır. `MealType` enum'u ile küme olarak birebir eşit
  /// olmalıdır (`import_sanitize_test.dart` sözleşme testiyle denetlenir).
  static const Set<String> mealTypeDbValues = {
    'breakfast',
    'lunch',
    'dinner',
    'snack',
  };

  // ------------------------------------------------------------------
  // EXPORT — web `exportData` parity: 8 paralel sorgu
  // ------------------------------------------------------------------

  /// Tüm kullanıcı verisini içeren JSON string üretir.
  Future<String> exportData(String userId) async {
    final profileFuture =
        _client.from('profiles').select().eq('id', userId).maybeSingle();
    final mealsFuture = _client
        .from('meal_entries')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null);
    final waterFuture = _client
        .from('water_entries')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null);
    final weightsFuture = _client
        .from('weight_entries')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null);
    final foodsFuture =
        _client.from('foods').select().eq('created_by', userId);
    final favoritesFuture =
        _client.from('favorite_foods').select().eq('user_id', userId);
    final recentsFuture =
        _client.from('recent_foods').select().eq('user_id', userId);
    final notifFuture = _client
        .from('notification_preferences')
        .select()
        .eq('user_id', userId);

    final results = await Future.wait<dynamic>([
      profileFuture,
      mealsFuture,
      waterFuture,
      weightsFuture,
      foodsFuture,
      favoritesFuture,
      recentsFuture,
      notifFuture,
    ]);

    final profile = results[0];
    final meals = results[1] as List;
    final water = results[2] as List;
    final weights = results[3] as List;
    final foods = results[4] as List;
    final favorites = results[5] as List;
    final recents = results[6] as List;
    final notifs = results[7] as List;

    // Kullanıcıya ait yemeklerin besin satırları (food_nutrition).
    final foodIds = <String>[
      for (final f in foods)
        if ((f as Map)['id'] != null) f['id'].toString(),
    ];
    final nutrition = <dynamic>[
      for (final chunk in inFilterChunks(foodIds))
        ...await _client
            .from('food_nutrition')
            .select()
            .inFilter('food_id', chunk) as List,
    ];

    final payload = <String, dynamic>{
      'version': AppConstants.appVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'profile': profile,
      'meal_entries': meals,
      'water_entries': water,
      'weight_entries': weights,
      'foods': foods,
      'food_nutrition': nutrition,
      'favorite_foods': favorites,
      'recent_foods': recents,
      'notification_preferences': notifs,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  // ------------------------------------------------------------------
  // IMPORT — web `importData` parity: doğrulama + dedup'lu eklemeli insert
  // ------------------------------------------------------------------

  /// Yedek JSON'unu doğrular ve eklemeli olarak içe aktarır.
  ///
  /// Döndürülen map eklenen kayıt sayılarını içerir.
  /// Geçersiz dosyada [FormatException] fırlatır.
  ///
  /// **Yumuşak silinen kayıtlar yeniden eklenmez.** Yedek `exportData`
  /// tarafından üretildiğinde zaten `deleted_at IS NULL` süzgecinden geçer,
  /// ancak elle düzenlenmiş bir yedek silinmiş satırlar içerebilir; bu
  /// durumda eski sürüm onları **yeniden "canlandırırdı"** (yeni `id` ile
  /// `deleted_at` boş bir satır) ve kullanıcı ilk sildiği öğünü geri
  /// buluyordu. Üç tablo (`meal_entries`, `water_entries`, `weight_entries`)
  /// yumuşak silme kullanır; `foods` tablosunda `deleted_at` kolonu yoktur.
  Future<Map<String, int>> importData(String userId, String jsonString) async {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] == null ||
        decoded['exportedAt'] == null) {
      throw const FormatException('Geçersiz CaloriX yedek dosyası');
    }
    final data = decoded;
    final counts = <String, int>{
      'foods': 0,
      'meal_entries': 0,
      'water_entries': 0,
      'weight_entries': 0,
    };

    // 1) Foods — dedup: name + created_by
    //
    // Dedup sorgusu tüm yedek isimlerini `in` filtresiyle **tek seferde**
    // çeker; döngü içinde `await` ile sorgu yapmak N+1 idi. Liste
    // [inFilterChunkSize] dilimlerine bölünür, aksi halde binlerce isimli
    // yedekte tek `in` listesi PostgREST'in ~8 KB URL tavanını aşar (414).
    // `maybeSingle()` 1'den fazla satırda `PGRST116` fırlattığı için (aynı
    // isimli iki kullanıcı yemeği mümkün — `foods` üzerinde UNIQUE yok)
    // liste kullanılır ve ilk eşleşme alınır.
    final foods = (data['foods'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final oldToNewFoodId = <String, String>{};

    final backupNames = <String>{
      for (final f in foods)
        if (f['name'] is String && (f['name'] as String).trim().isNotEmpty)
          (f['name'] as String).trim(),
    }.toList();
    final existingFoods = <String, String>{};
    for (final chunk in inFilterChunks(backupNames)) {
      final rows = await _client
          .from('foods')
          .select('id, name')
          .eq('created_by', userId)
          .inFilter('name', chunk);
      for (final row in rows as List) {
        final name = (row as Map)['name'] as String?;
        if (name != null) existingFoods.putIfAbsent(name, () => row['id'] as String);
      }
    }

    for (final food in foods) {
      final name = food['name'];
      if (name is! String || name.trim().isEmpty) continue;
      final key = name.trim();
      final oldId = food['id']?.toString();
      if (oldId == null) continue;

      final existingId = existingFoods[key];
      if (existingId != null) {
        oldToNewFoodId[oldId] = existingId;
        continue;
      }
      final cleaned = sanitizeFood(food)
        ..['name'] = key
        ..['created_by'] = userId
        ..remove('food_nutrition');
      final inserted = await _client
          .from('foods')
          .insert(cleaned)
          .select('id')
          .single();
      oldToNewFoodId[oldId] = inserted['id'].toString();
      existingFoods[key] = oldToNewFoodId[oldId]!;
      counts['foods'] = counts['foods']! + 1;
    }

    // 2) food_nutrition — yeni food_id ile yeniden ekle
    //
    // `food_nutrition.food_id` UNIQUE (`full_setup.sql:121`): aynı gıdaya
    // ikinci besin satırı eklemek `23505 duplicate key` ile **tüm import'u**
    // düşürürdu. Yedekte aynı `food_id` için birden çok satır varsa ilki
    // kazanır (deterministik), geri kalanı atlanır.
    final nutrition =
        (data['food_nutrition'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final seenFoodIds = <String>{};
    for (final n in nutrition) {
      final newFoodId = oldToNewFoodId[n['food_id']?.toString()];
      if (newFoodId == null) continue;
      if (!seenFoodIds.add(newFoodId)) continue;
      final cleaned = _sanitizeNutrition(n)..['food_id'] = newFoodId;
      await _client.from('food_nutrition').insert(cleaned);
    }

    // 3) meal_entries — dedup: user_id + entry_date + custom_name + meal_type
    //
    // `meal_entries` üzerinde bu kombinasyona UNIQUE constraint yoktur, bu
    // yüzden `maybeSingle()` **birden fazla eşleşmede istisna fırlatır** ve
    // içe aktarma tamamen çöker (aynı gün/öğünde iki ayrı "Tavuk" kaydı
    // yedeklenmiş olan kullanıcılar için 100% olası). Varlık kontrolü
    // `in`-filtreli sorgularla yapılır (tarihler dilimli — bkz.
    // [inFilterChunkSize]), ekleme hâlâ satır satır (aynı `created_at`
    // sırasını korumak için) yapılır.
    // Yumuşak silinmiş satırlar **varlık kontrolüne de** girmemeli: aksi
    // halde DB'deki canlı ama farklı kayıtla aynı anahtarı taşıyan bir
    // silinmiş satın varlığı, canlı satırın yeniden eklenmesini engeller.
    final meals = _liveRows((data['meal_entries'] as List?)?.cast());
    final existingMealKeys = await _existingMealKeys(userId, meals);
    for (final m in meals) {
      // Yumuşak silinmiş kayıt yeniden eklenmez (bkz. [importData] docu).
      if (isDeleted(m)) continue;
      final key = _mealKey(m);
      if (key == null) continue;
      if (existingMealKeys.contains(key)) continue;
      final cleaned = _sanitizeMealEntry(m, userId, oldToNewFoodId);
      await _client.from('meal_entries').insert(cleaned);
      existingMealKeys.add(key);
      counts['meal_entries'] = counts['meal_entries']! + 1;
    }

    // 4) water_entries — dedup: entry_time
    // `entry_time` timestamptz NOT NULL UNIQUE değil → `maybeSingle()` iki
    // kayıtta patlar. Aynı kombinasyon anahtarı ile toplu kontrol yapılır.
    final waters = _liveRows((data['water_entries'] as List?)?.cast());
    final existingWaterTimes = await _existingWaterTimes(
      userId,
      times: [
        for (final w in waters)
          if (w['entry_time'] is String) w['entry_time'] as String,
      ],
    );
    for (final w in waters) {
      if (isDeleted(w)) continue;
      final time = w['entry_time'];
      if (time is! String || time.isEmpty) continue;
      if (existingWaterTimes.contains(time)) continue;
      final cleaned = _sanitizeWaterEntry(w, userId);
      await _client.from('water_entries').insert(cleaned);
      existingWaterTimes.add(time);
      counts['water_entries'] = counts['water_entries']! + 1;
    }

    // 5) weight_entries — dedup: entry_date
    // Aynı gün iki kilo kaydı olabilir (UNIQUE constraint yok) →
    // `maybeSingle()` yerine toplu `in` kontrolü.
    final weights = _liveRows((data['weight_entries'] as List?)?.cast());
    final weightDates = <String>{
      for (final w in weights)
        if (w['entry_date'] is String) w['entry_date'] as String,
    }.toList();
    final existingWeightDates = <String>{};
    for (final chunk in inFilterChunks(weightDates)) {
      final rows = await _client
          .from('weight_entries')
          .select('entry_date')
          .eq('user_id', userId)
          .inFilter('entry_date', chunk);
      for (final row in rows as List) {
        final d = (row as Map)['entry_date'] as String?;
        if (d != null) existingWeightDates.add(d);
      }
    }
    for (final w in weights) {
      if (isDeleted(w)) continue;
      final date = w['entry_date'];
      if (date is! String || date.isEmpty) continue;
      if (existingWeightDates.contains(date)) continue;
      final cleaned = _sanitizeWeightEntry(w, userId);
      await _client.from('weight_entries').insert(cleaned);
      existingWeightDates.add(date);
      counts['weight_entries'] = counts['weight_entries']! + 1;
    }

    return counts;
  }

  /// `meal_entries` yedeğini DB sözleşmesine göre beyaz listeler.
  ///
  /// `meal_type` ve `source` enum alanları: yedek bozuk/eskiden kalma bir
  /// değer taşırsa (`'brunch'`, `'barcode'`) insert CHECK ihlaliyle 400 döner
  /// ve **tüm içe aktarma** orada durur. Geçersiz değerler DB varsayılanına
  /// çekilir: `meal_type` → `'snack'`, `source` → `'manual'`.
  ///
  /// `food_id` yedeğin eski UUID'sidir → içe aktarımda kullanıcının yeni
  /// gıda id'siyle değiştirilir; karşılık yoksa `null` (manuel girdi).
  static Map<String, dynamic> _sanitizeMealEntry(
    Map<String, dynamic> m,
    String userId,
    Map<String, String> oldToNewFoodId,
  ) {
    const allowed = <String>[
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
    ];
    final out = <String, dynamic>{
      for (final k in allowed)
        if (m.containsKey(k) && m[k] != null) k: m[k],
    };
    out['user_id'] = userId;
    out['food_id'] = oldToNewFoodId[m['food_id']?.toString()];
    if (!DataTransferRepository.mealTypeDbValues.contains(out['meal_type'])) {
      out['meal_type'] = 'snack';
    }
    if (!_sanitizeFoodSource.contains(out['source'])) {
      out['source'] = 'manual';
    }
    return out;
  }

  /// `water_entries` yedeğini beyaz listeler — `amount_ml` `INTEGER NOT NULL`
  /// olduğu için küsüratlı/string değer 400 üretir.
  static Map<String, dynamic> _sanitizeWaterEntry(
    Map<String, dynamic> w,
    String userId,
  ) {
    const allowed = <String>['entry_date', 'entry_time', 'amount_ml'];
    final out = <String, dynamic>{
      for (final k in allowed)
        if (w.containsKey(k) && w[k] != null) k: w[k],
    };
    out['user_id'] = userId;
    final ml = out['amount_ml'];
    if (ml is num && ml.isFinite) {
      out['amount_ml'] = ml.round();
    } else {
      out['amount_ml'] = 0;
    }
    return out;
  }

  /// `weight_entries` yedeğini beyaz listeler — `weight_kg NUMERIC(5,2)
  /// NOT NULL`; negatif/bozuk değer 400 üretir.
  static Map<String, dynamic> _sanitizeWeightEntry(
    Map<String, dynamic> w,
    String userId,
  ) {
    const allowed = <String>['entry_date', 'weight_kg', 'note'];
    final out = <String, dynamic>{
      for (final k in allowed)
        if (w.containsKey(k) && w[k] != null) k: w[k],
    };
    out['user_id'] = userId;
    final kg = out['weight_kg'];
    out['weight_kg'] = (kg is num && kg.isFinite && kg > 0) ? kg.toDouble() : 0.0;
    return out;
  }

  /// `food_source` enum değerleri (`20260822000000_remove_barcode.sql`).
  static const Set<String> _sanitizeFoodSource = {'photo', 'text', 'manual'};

  /// `food_nutrition` yedeğini DB sözleşmesine göre beyaz listeler.
  ///
  /// Aynı nedenle kara liste uygulanmaz: yedekteki tanınmayan kolon
  /// PostgREST 400'üne ve import'un tamamının düşmesine yol açar.
  /// `kcal/protein_g/carbs_g/fat_g` `NOT NULL` olduğu için sayısal olmayan
  /// (null/string) değerler 0'a çevrilir — aksi halde 400.
  static Map<String, dynamic> _sanitizeNutrition(Map<String, dynamic> n) {
    const allowed = <String>[
      'per_100_g_ml',
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
    ];
    final out = <String, dynamic>{
      for (final k in allowed)
        if (n.containsKey(k) && n[k] != null) k: n[k],
    };
    for (final k in const ['kcal', 'protein_g', 'carbs_g', 'fat_g']) {
      final v = out[k];
      if (v is! num) {
        out[k] = 0;
      } else {
        final d = v.toDouble();
        out[k] = d.isFinite ? d : 0;
      }
    }
    return out;
  }

  /// `foods` yedeğini DB sözleşmesine göre beyaz listeler.
  ///
  /// `_stripIds` **beyaz liste değil, kara liste** uygular: yedekte
  /// tanımadığı her kolon (`dietary_...`, `barcode`, `last_synced_at`,
  /// `sync_state`, eski web istemcisinin eklediği alanlar) insert'e
  /// gönderilir ve PostgREST `PGRST204` ile **400** döner:
  /// "Could not find the 'column' in the schema cache". Bu, tek bozuk alanın
  /// **tüm içe aktarımı** düşürmesidir (`importData` satır satır yazıyor,
  /// hata fırlıyor, geri kalan kayıtlar hiç eklenmiyor).
  ///
  /// `foods.source` allow-list'i de burada uygulanır: enum
  /// (`photo|text|manual`) dışı bir değer (`barcode` gibi eski bir yedek)
  /// insert'i CHECK ihlaliyle reddeder. Web (`src/hooks/useDataExport.ts:162`)
  /// aynı korumayı yapıyor; burada liste genişletilmiştir.
  static Map<String, dynamic> sanitizeFood(Map<String, dynamic> food) {
    const allowed = <String>[
      'name',
      'brand',
      'serving_size_g',
      'serving_description',
      'source',
      'image_url',
      'popularity_count',
      'verified',
      'created_by',
    ];
    final out = <String, dynamic>{
      for (final k in allowed)
        if (food.containsKey(k) && food[k] != null) k: food[k],
    };
    // Enum dışı `source` → DB varsayılanı ('manual').
    const sources = <String>{'photo', 'text', 'manual'};
    final source = out['source'];
    if (source is! String || !sources.contains(source)) out['source'] = 'manual';
    return out;
  }

  /// Yedeğin `meal_entries` dedup anahtarları
  /// (`entry_date|custom_name|meal_type`).
  ///
  /// Saf yardımcı — içe aktarma yolunda kullanılmaz (varlık kontrolü
  /// `_existingMealKeys` ile yapılır) ama sözleşmesi testte doğrulanır:
  /// anahtar biçimi değişirse dedup sessizce bozulur.
  static List<String> mealKeysOf(List<Map<String, dynamic>> rows) {
    final out = <String>{};
    for (final m in rows) {
      final k = _mealKey(m);
      if (k != null) out.add(k);
    }
    return out.toList();
  }

  /// [values] listesini [inFilterChunkSize] boyutunda dilimlere böler.
  ///
  /// Boş girdi **tek boş dilim** döndürür, yani çağıran `if (isNotEmpty)`
  /// kontrolü yapmasa bile `in.()` üretmez (PostgREST bunu `PGRST100`
  /// "Syntax error" ile reddeder).
  static List<List<T>> inFilterChunks<T>(List<T> values) {
    if (values.isEmpty) return const [];
    return [
      for (var i = 0; i < values.length; i += inFilterChunkSize)
        values.sublist(i, (i + inFilterChunkSize).clamp(0, values.length)),
    ];
  }

  /// Yedek satırlarından `deleted_at` **dolu** olanları ayıklar.
  ///
  /// Eleme yapılmazsa sessiz veri bozulması olur: `_stripIds` `deleted_at`
  /// kolonunu kaldırdığı için silinmiş bir kayıt yeniden eklenirse
  /// **canlanır** (yeni `id`, `deleted_at = NULL`) ve kullanıcı ilk sildiği
  /// öğünü/kilo kaydını geri bulur. Yedek `exportData` tarafından üretilmişse
  /// zaten süzgeçten geçmiş olur; elle düzenlenmiş yedeklerde bu eleme
  /// asıl korumadır.
  static List<Map<String, dynamic>> _liveRows(List<Map<String, dynamic>>? raw) =>
      [
        for (final row in raw ?? const <Map<String, dynamic>>[])
          if (!isDeleted(row)) row,
      ];

  /// Satır yumuşak silinmiş mi (`deleted_at` dolu)?
  ///
  /// `_stripIds` `deleted_at` kolonunu içe aktarımda zaten kaldırıyor —
  /// **bu olmadan** silinmiş bir kayıt yeniden eklenirdi. Kullanıcı ilk
  /// sildiği öğünü/su kaydını yedekten geri getirdiğinde "sildim ama geri
  /// geldi" diyecekti. `deleted_at` kolonu **yalnız bu üç tabloda** vardır
  /// (`foods` tablosunda yoktur); eksik alan silinmemiş sayılır.
  @visibleForTesting
  static bool isDeleted(Map<String, dynamic> row) {
    final v = row['deleted_at'];
    if (v == null) return false;
    if (v is String) return v.isNotEmpty;
    return true;
  }

  /// `null` → anahtarsız (import'ta atlanacak satır).
  static String? _mealKey(Map<String, dynamic> m) {
    final date = m['entry_date'];
    final type = m['meal_type'];
    if (date is! String || date.isEmpty) return null;
    if (type is! String || type.isEmpty) return null;
    final name = (m['custom_name'] ?? '') as String;
    return '$date|$name|$type';
  }

  /// Kullanıcının mevcut öğün kayıtlarının dedup anahtarları.
  ///
  /// Tarihler [inFilterChunkSize] dilimlerine bölünür: yedek binlerce
  /// günü kapsadığında tek `in` listesi PostgREST'in ~8 KB URL tavanını
  /// aşar ve içe aktarma 414 ile düşer.
  Future<Set<String>> _existingMealKeys(
    String userId,
    List<Map<String, dynamic>> backupRows,
  ) async {
    final keys = <String>{};
    final dates = <String>{
      for (final m in backupRows)
        if (m['entry_date'] is String && (m['entry_date'] as String).isNotEmpty)
          m['entry_date'] as String,
    }.toList();
    for (final chunk in inFilterChunks(dates)) {
      final rows = await _client
          .from('meal_entries')
          .select('entry_date, custom_name, meal_type')
          .eq('user_id', userId)
          .inFilter('entry_date', chunk);
      for (final row in rows as List) {
        final k = _mealKey(row as Map<String, dynamic>);
        if (k != null) keys.add(k);
      }
    }
    return keys;
  }

  /// Kullanıcının mevcut `entry_time` değerleri — tek sorgu.
  Future<Set<String>> _existingWaterTimes(
    String userId, {
    List<String>? times,
  }) async {
    final out = <String>{};
    if (times == null) {
      // Tüm zamanlar (yedekte olmayan ama aynı anda yazılan kayıtlar).
      final rows = await _client
          .from('water_entries')
          .select('entry_time')
          .eq('user_id', userId);
      for (final row in rows as List) {
        final t = (row as Map)['entry_time']?.toString();
        if (t != null) out.add(t);
      }
      return out;
    }
    final wanted = times.toSet();
    // `in` filtresi timestamptz için ISO string kabul eder. ISO 8601 damgalar
    // (`2026-08-15T10:00:00.000Z`, 24 bayt + 2 tırnak) en uzun değerlerdir:
    // 1000'lik yedek tek sorguda ~27 KB, 5000'lik yedekte 135 KB olurdu.
    for (final chunk in inFilterChunks(wanted.toList())) {
      final rows = await _client
          .from('water_entries')
          .select('entry_time')
          .eq('user_id', userId)
          .inFilter('entry_time', chunk);
      for (final row in rows as List) {
        final t = (row as Map)['entry_time']?.toString();
        if (t != null) out.add(t);
      }
    }
    return out;
  }
}

final dataTransferRepositoryProvider = Provider<DataTransferRepository>((ref) {
  return DataTransferRepository(ref.watch(supabaseClientProvider));
});

/// Oturum açık kullanıcı id kısayolu.
String? currentUserId(Ref ref) => ref.watch(currentUserProvider)?.id;
