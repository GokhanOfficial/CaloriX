import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/food_item.dart';
import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';

/// Yemek arama + favoriler + son yenilenler.
///
/// Web karşılıkları: `useFoodSearch.ts`, `useFavoriteFoods.ts`,
/// `useRecentFoods.ts`. Sorgu şekilleri, limitler, dedup (küçük harf isim)
/// ve 100g normalizasyon formülleri web ile birebir aynıdır.
class FoodRepository {
  FoodRepository(this._client);

  final SupabaseClient _client;

  /// Metin araması — min 2 karakter. Önce `foods` tablosu (popülerlik
  /// sıralı, limit 10), sonra kullanıcının custom girdileri
  /// (`food_id IS NULL`, limit 50). İsme göre (küçük harf) dedup,
  /// DB yemekleri önde olacak şekilde ilk 15 sonuç.
  Future<List<FoodItem>> search(String userId, String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    final results = <FoodItem>[];
    final seenNames = <String>{};

    // 1) Veritabanı yemekleri (nutrition join ile)
    final dbFoods = await _client
        .from('foods')
        .select('id, name, brand, serving_size_g, '
            'food_nutrition(kcal, protein_g, carbs_g, fat_g)')
        .ilike('name', '%$q%')
        .order('popularity_count', ascending: false)
        .limit(10);

    for (final row in dbFoods) {
      final nutrition = _firstNutrition(row['food_nutrition']);
      if (nutrition == null) continue;
      final name = row['name'] as String;
      final key = name.toLowerCase();
      if (!seenNames.add(key)) continue;
      results.add(FoodItem(
        id: row['id'] as String,
        foodId: row['id'] as String,
        name: name,
        brand: row['brand'] as String?,
        servingSizeG: (row['serving_size_g'] as num?)?.toDouble(),
        calories: (nutrition['kcal'] as num).toDouble(),
        proteinG: (nutrition['protein_g'] as num).toDouble(),
        carbsG: (nutrition['carbs_g'] as num).toDouble(),
        fatG: (nutrition['fat_g'] as num).toDouble(),
      ));
    }

    // 2) Kullanıcının custom (manuel) girdileri — 100g'a normalize
    final customFoods = await _client
        .from('meal_entries')
        .select('id, custom_name, amount_g_ml, calculated_kcal, '
            'calculated_protein, calculated_carbs, calculated_fat, food_id')
        .eq('user_id', userId)
        .filter('deleted_at', 'is', null)
        .filter('food_id', 'is', null)
        .ilike('custom_name', '%$q%')
        .order('created_at', ascending: false)
        .limit(50);

    for (final row in customFoods) {
      final customName = row['custom_name'] as String?;
      if (customName == null || customName.isEmpty) continue;
      final key = customName.toLowerCase();
      if (!seenNames.add(key)) continue;
      results.add(_customItem(row, idPrefix: 'custom_'));
    }

    // DB yemekleri önce, custom sonra (web parity — stable sort)
    results.sort((a, b) {
      if (a.isCustom && !b.isCustom) return 1;
      if (!a.isCustom && b.isCustom) return -1;
      return 0;
    });

    return results.take(15).toList();
  }

  /// En sık yenilen 10 yemek — son 200 girdiden isim bazlı frekans
  /// sayımı (web `useFavoriteFoods` parity).
  Future<List<FoodItem>> favorites(String userId) async {
    final rows = await _client
        .from('meal_entries')
        .select('id, food_id, custom_name, amount_g_ml, calculated_kcal, '
            'calculated_protein, calculated_carbs, calculated_fat, '
            'foods(id, name, brand, serving_size_g, '
            'food_nutrition(kcal, protein_g, carbs_g, fat_g))')
        .eq('user_id', userId)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false)
        .limit(200);

    // isim(küçük harf) → {count, row} — ilk görülen row tutulur
    final counts = <String, int>{};
    final firstRow = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final name = _rowName(row);
      final key = name.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      firstRow.putIfAbsent(key, () => row);
    }

    final keys = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    return keys.take(10).map((key) {
      final row = firstRow[key]!;
      return _rowToItem(row, useCount: counts[key]);
    }).toList();
  }

  /// Son yenilen 10 benzersiz yemek — son 50 girdiden isim bazlı dedup
  /// (web `useRecentFoods` parity).
  Future<List<FoodItem>> recents(String userId) async {
    final rows = await _client
        .from('meal_entries')
        .select('id, food_id, custom_name, amount_g_ml, calculated_kcal, '
            'calculated_protein, calculated_carbs, calculated_fat, created_at, '
            'foods(id, name, brand, serving_size_g, '
            'food_nutrition(kcal, protein_g, carbs_g, fat_g))')
        .eq('user_id', userId)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: false)
        .limit(50);

    final seen = <String>{};
    final items = <FoodItem>[];
    for (final row in rows) {
      final name = _rowName(row);
      if (!seen.add(name.toLowerCase())) continue;
      items.add(_rowToItem(row, lastUsedAt: row['created_at'] as String?));
      if (items.length >= 10) break;
    }
    return items;
  }

  // --- yardımcılar -------------------------------------------------------

  /// Row'daki görünen isim: join varsa foods.name, yoksa custom_name.
  static String _rowName(Map<String, dynamic> row) {
    final foods = row['foods'];
    if (foods is Map<String, dynamic>) {
      return foods['name'] as String? ?? 'Bilinmeyen';
    }
    return row['custom_name'] as String? ?? 'Bilinmeyen';
  }

  static Map<String, dynamic>? _firstNutrition(Object? join) {
    // PostgREST 1:1 join'i bazen Map, bazen tek elemanlı List döndürür.
    if (join is Map<String, dynamic>) return join;
    if (join is List && join.isNotEmpty) {
      return join.first as Map<String, dynamic>;
    }
    return null;
  }

  static FoodItem _rowToItem(
    Map<String, dynamic> row, {
    int? useCount,
    String? lastUsedAt,
  }) {
    final foods = row['foods'];
    final nutrition = foods is Map<String, dynamic>
        ? _firstNutrition(foods['food_nutrition'])
        : null;

    if (foods is Map<String, dynamic> && nutrition != null) {
      return FoodItem(
        id: row['id'] as String,
        foodId: row['food_id'] as String?,
        name: foods['name'] as String? ?? 'Bilinmeyen',
        brand: foods['brand'] as String?,
        servingSizeG: (foods['serving_size_g'] as num?)?.toDouble(),
        calories: (nutrition['kcal'] as num).toDouble(),
        proteinG: (nutrition['protein_g'] as num).toDouble(),
        carbsG: (nutrition['carbs_g'] as num).toDouble(),
        fatG: (nutrition['fat_g'] as num).toDouble(),
        useCount: useCount,
        lastUsedAt: lastUsedAt,
      );
    }
    return _customItem(row, useCount: useCount, lastUsedAt: lastUsedAt);
  }

  /// Custom (food_id IS NULL) girdiyi 100g başına değerlere çevirir.
  /// Web formülü: kcal round(x/amount*100), makrolar round1(x/amount*100),
  /// amount = amount_g_ml ?? 100.
  static FoodItem _customItem(
    Map<String, dynamic> row, {
    String idPrefix = '',
    int? useCount,
    String? lastUsedAt,
  }) {
    final amount = (row['amount_g_ml'] as num?)?.toDouble() ?? 100;
    double per100(String column) =>
        ((row[column] as num?)?.toDouble() ?? 0) / amount * 100;
    double round1(double v) => (v * 10).round() / 10;

    return FoodItem(
      id: '$idPrefix${row['id']}',
      name: row['custom_name'] as String? ?? 'Bilinmeyen',
      servingSizeG: amount,
      calories: per100('calculated_kcal').roundToDouble(),
      proteinG: round1(per100('calculated_protein')),
      carbsG: round1(per100('calculated_carbs')),
      fatG: round1(per100('calculated_fat')),
      isCustom: true,
      useCount: useCount,
      lastUsedAt: lastUsedAt,
    );
  }
}

final foodRepositoryProvider = Provider<FoodRepository>((ref) {
  return FoodRepository(ref.watch(supabaseClientProvider));
});

/// Arama sonuçları — debounce UI katmanında (AddPage) yapılır.
final foodSearchProvider =
    FutureProvider.autoDispose.family<List<FoodItem>, String>((ref, query) {
  final user = ref.watch(currentUserProvider);
  if (user == null || query.trim().length < 2) return const [];
  return ref.watch(foodRepositoryProvider).search(user.id, query);
});

/// En sık yenilenler (web `useFavoriteFoods`).
final favoriteFoodsProvider = FutureProvider<List<FoodItem>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(foodRepositoryProvider).favorites(user.id);
});

/// Son yenilenler (web `useRecentFoods`).
final recentFoodsProvider = FutureProvider<List<FoodItem>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(foodRepositoryProvider).recents(user.id);
});
