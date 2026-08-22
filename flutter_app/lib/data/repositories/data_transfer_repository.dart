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
    List nutrition = const [];
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
    final foods = (data['foods'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final oldToNewFoodId = <String, String>{};
    for (final food in foods) {
      final name = food['name'];
      final existing = await _client
          .from('foods')
          .select('id')
          .eq('created_by', userId)
          .eq('name', name)
          .maybeSingle();
      if (existing != null) {
        oldToNewFoodId[food['id'].toString()] = existing['id'].toString();
        continue;
      }
      final cleaned = _stripIds(food)
        ..['created_by'] = userId
        ..remove('food_nutrition');
      final inserted = await _client
          .from('foods')
          .insert(cleaned)
          .select('id')
          .single();
      oldToNewFoodId[food['id'].toString()] = inserted['id'].toString();
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
    final meals =
        (data['meal_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final m in meals) {
      final exists = await _client
          .from('meal_entries')
          .select('id')
          .eq('user_id', userId)
          .eq('entry_date', m['entry_date'])
          .eq('custom_name', m['custom_name'] ?? '')
          .eq('meal_type', m['meal_type'])
          .maybeSingle();
      if (exists != null) continue;
      final cleaned = _stripIds(m)
        ..['user_id'] = userId
        ..['food_id'] = oldToNewFoodId[m['food_id']?.toString()];
      await _client.from('meal_entries').insert(cleaned);
      counts['meal_entries'] = counts['meal_entries']! + 1;
    }

    // 4) water_entries — dedup: entry_time
    final waters =
        (data['water_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final w in waters) {
      final exists = await _client
          .from('water_entries')
          .select('id')
          .eq('user_id', userId)
          .eq('entry_time', w['entry_time'])
          .maybeSingle();
      if (exists != null) continue;
      final cleaned = _stripIds(w)..['user_id'] = userId;
      await _client.from('water_entries').insert(cleaned);
      counts['water_entries'] = counts['water_entries']! + 1;
    }

    // 5) weight_entries — dedup: entry_date
    final weights =
        (data['weight_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final w in weights) {
      final exists = await _client
          .from('weight_entries')
          .select('id')
          .eq('user_id', userId)
          .eq('entry_date', w['entry_date'])
          .maybeSingle();
      if (exists != null) continue;
      final cleaned = _stripIds(w)..['user_id'] = userId;
      await _client.from('weight_entries').insert(cleaned);
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
}

final dataTransferRepositoryProvider = Provider<DataTransferRepository>((ref) {
  return DataTransferRepository(ref.watch(supabaseClientProvider));
});

/// Oturum açık kullanıcı id kısayolu.
String? currentUserId(Ref ref) => ref.watch(currentUserProvider)?.id;
