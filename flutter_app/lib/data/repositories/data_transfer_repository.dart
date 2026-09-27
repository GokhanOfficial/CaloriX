import 'dart:convert';

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
    List<dynamic> nutrition = const [];
    if (foodIds.isNotEmpty) {
      nutrition = await _client
          .from('food_nutrition')
          .select()
          .inFilter('food_id', foodIds) as List;
    }

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
    // Dedup sorgusu **tek seferde** tüm yedek isimlerini çeker (`in` filtresi
    // ile); döngü içinde `await` ile sorgu yapmak N+1 idi. `maybeSingle()`
    // 1'den fazla satırda `PGRST116` fırlattığı için (aynı isimli iki
    // kullanıcı yemeği mümkün — `foods` üzerinde UNIQUE yok) liste
    // kullanılır ve ilk eşleşme alınır.
    final foods = (data['foods'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final oldToNewFoodId = <String, String>{};

    final backupNames = <String>{
      for (final f in foods)
        if (f['name'] is String && (f['name'] as String).trim().isNotEmpty)
          (f['name'] as String).trim(),
    }.toList();
    final existingFoods = <String, String>{};
    if (backupNames.isNotEmpty) {
      final rows = await _client
          .from('foods')
          .select('id, name')
          .eq('created_by', userId)
          .inFilter('name', backupNames);
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
      final cleaned = _stripIds(food)
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
    final nutrition =
        (data['food_nutrition'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final n in nutrition) {
      final newFoodId = oldToNewFoodId[n['food_id']?.toString()];
      if (newFoodId == null) continue;
      final cleaned = _stripIds(n)..['food_id'] = newFoodId;
      await _client.from('food_nutrition').insert(cleaned);
    }

    // 3) meal_entries — dedup: user_id + entry_date + custom_name + meal_type
    //
    // `meal_entries` üzerinde bu kombinasyona UNIQUE constraint yoktur, bu
    // yüzden `maybeSingle()` **birden fazla eşleşmede istisna fırlatır** ve
    // içe aktarma tamamen çöker (aynı gün/öğünde iki ayrı "Tavuk" kaydı
    // yedeklenmiş olan kullanıcılar için 100% olası). Varlık kontrolü tek
    // `in`-filtreli sorguyla yapılır, ekleme hâlâ satır satır (aynı
    // `created_at` sırasını korumak için) yapılır.
    final meals =
        (data['meal_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final existingMealKeys =
        await _existingMealKeys(userId, _mealKeysOf(meals).isEmpty
            ? null
            : meals);
    for (final m in meals) {
      final key = _mealKey(m);
      if (key == null) continue;
      if (existingMealKeys.contains(key)) continue;
      final cleaned = _stripIds(m)
        ..['user_id'] = userId
        ..['food_id'] = oldToNewFoodId[m['food_id']?.toString()];
      await _client.from('meal_entries').insert(cleaned);
      existingMealKeys.add(key);
      counts['meal_entries'] = counts['meal_entries']! + 1;
    }

    // 4) water_entries — dedup: entry_time
    // `entry_time` timestamptz NOT NULL UNIQUE değil → `maybeSingle()` iki
    // kayıtta patlar. Aynı kombinasyon anahtarı ile toplu kontrol yapılır.
    final waters =
        (data['water_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final existingWaterTimes = await _existingWaterTimes(
      userId,
      times: [
        for (final w in waters)
          if (w['entry_time'] is String) w['entry_time'] as String,
      ],
    );
    for (final w in waters) {
      final time = w['entry_time'];
      if (time is! String || time.isEmpty) continue;
      if (existingWaterTimes.contains(time)) continue;
      final cleaned = _stripIds(w)..['user_id'] = userId;
      await _client.from('water_entries').insert(cleaned);
      existingWaterTimes.add(time);
      counts['water_entries'] = counts['water_entries']! + 1;
    }

    // 5) weight_entries — dedup: entry_date
    // Aynı gün iki kilo kaydı olabilir (UNIQUE constraint yok) →
    // `maybeSingle()` yerine toplu `in` kontrolü.
    final weights =
        (data['weight_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final weightDates = <String>{
      for (final w in weights)
        if (w['entry_date'] is String) w['entry_date'] as String,
    }.toList();
    final existingWeightDates = <String>{};
    if (weightDates.isNotEmpty) {
      final rows = await _client
          .from('weight_entries')
          .select('entry_date')
          .eq('user_id', userId)
          .inFilter('entry_date', weightDates);
      for (final row in rows as List) {
        final d = (row as Map)['entry_date'] as String?;
        if (d != null) existingWeightDates.add(d);
      }
    }
    for (final w in weights) {
      final date = w['entry_date'];
      if (date is! String || date.isEmpty) continue;
      if (existingWeightDates.contains(date)) continue;
      final cleaned = _stripIds(w)..['user_id'] = userId;
      await _client.from('weight_entries').insert(cleaned);
      existingWeightDates.add(date);
      counts['weight_entries'] = counts['weight_entries']! + 1;
    }

    return counts;
  }

  /// Yeniden insert için kimlik/zaman damgası alanlarını temizler.
  Map<String, dynamic> _stripIds(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    copy.remove('id');
    copy.remove('created_at');
    copy.remove('updated_at');
    copy.remove('deleted_at');
    return copy;
  }

  /// Yedeğin `meal_entries` dedup anahtarları
  /// (`entry_date|custom_name|meal_type`).
  static List<String> _mealKeysOf(List<Map<String, dynamic>> rows) {
    final out = <String>{};
    for (final m in rows) {
      final k = _mealKey(m);
      if (k != null) out.add(k);
    }
    return out.toList();
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

  /// Kullanıcının mevcut öğün kayıtlarının dedup anahtarları — tek sorgu.
  Future<Set<String>> _existingMealKeys(
    String userId,
    List<Map<String, dynamic>>? backupRows,
  ) async {
    final keys = <String>{};
    final dates = <String>{
      if (backupRows != null)
        for (final m in backupRows)
          if (m['entry_date'] is String) m['entry_date'] as String,
    }.toList();
    if (dates.isEmpty) return keys;
    final rows = await _client
        .from('meal_entries')
        .select('entry_date, custom_name, meal_type')
        .eq('user_id', userId)
        .inFilter('entry_date', dates);
    for (final row in rows as List) {
      final k = _mealKey(row as Map<String, dynamic>);
      if (k != null) keys.add(k);
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
    if (wanted.isEmpty) return out;
    // `in` filtresi timestamptz için ISO string kabul eder.
    final rows = await _client
        .from('water_entries')
        .select('entry_time')
        .eq('user_id', userId)
        .inFilter('entry_time', wanted.toList());
    for (final row in rows as List) {
      final t = (row as Map)['entry_time']?.toString();
      if (t != null) out.add(t);
    }
    return out;
  }
}

final dataTransferRepositoryProvider = Provider<DataTransferRepository>((ref) {
  return DataTransferRepository(ref.watch(supabaseClientProvider));
});

/// Oturum açık kullanıcı id kısayolu.
String? currentUserId(Ref ref) => ref.watch(currentUserProvider)?.id;
