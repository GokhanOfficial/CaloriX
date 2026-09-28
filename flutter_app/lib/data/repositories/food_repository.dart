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
///
/// Favoriler artık **türetilmiyor**: `favorite_foods` tablosu kaynaktır
/// (A4r7, ürün kararı 1-A). Türetilmiş "en çok yenilenler" listesi
/// [frequentFoods] altında korunur — `addFood.favorites` bölümü bugün
/// **kullanıcının seçtiği** favorileri, `addFood.recent` ise türetilmiş
/// son-50-öğün listesini gösterir.
class FoodRepository {
  FoodRepository(this._client);

  final SupabaseClient _client;

  /// `favorite_foods` tablosu (`full_setup.sql:185-192`).
  ///
  /// - `user_id` `NOT NULL` + RLS `auth.uid() = user_id` → satır **her
  ///   zaman** kullanıcının kendi id'siyle yazılır.
  /// - `food_id` `NOT NULL` FK → `null` yazılamaz; ekleme yalnızca `foods`
  ///   tablosundaki bir kayda yapılabilir (custom/manual girdilerin
  ///   `food_id`'si yoktur, bu yüzden favori olamazlar).
  /// - `UNIQUE(user_id, food_id)` → tekrar ekleme `23505` yerine
  ///   [addFavorite]'in upsert'i ile **idempotent** olur.
  static const favoriteTable = 'favorite_foods';

  /// Favoriye ekler (idempotent). `ON CONFLICT (user_id, food_id) DO
  /// NOTHING` kullanılır: kullanıcı zaten eklemişse **hata fırlatmaz**
  /// (çift dokunma / iki cihazda aynı anda ekleme sessizce yutulmaz,
  /// idempotent olur).
  ///
  /// `created_at` **bilinçli olarak gönderilmez**: kolon `DEFAULT now()` ile
  /// doludur ve istemciden gönderilmesi A2r5'in "created_at sözleşmeye
  /// girmiyordu" hatasının aynısıdır.
  Future<void> addFavorite(String userId, String foodId) async {
    await _client
        .from(favoriteTable)
        .upsert(
          {'user_id': userId, 'food_id': foodId},
          onConflict: 'user_id,food_id',
          ignoreDuplicates: true,
        );
  }

  /// Favoriden çıkarır. Satır yoksa da hata **fırlatmaz** (`DELETE` 0 satır
  /// döner): kullanıcı zaten kaldırmışsa "kaldır" işlemi de idempotent'tir.
  Future<void> removeFavorite(String userId, String foodId) async {
    await _client
        .from(favoriteTable)
        .delete()
        .eq('user_id', userId)
        .eq('food_id', foodId);
  }

  /// Gıdanın favori olup olmadığı. `EXISTS` yerine tek satır `select`
  /// kullanılır (PostgREST `head`/`count` başlıkları her istemci sürümünde
  /// tutarlı değil; `maybeSingle` + `data != null` taşınabilir).
  Future<bool> isFavorite(String userId, String foodId) async {
    final row = await _client
        .from(favoriteTable)
        .select('id')
        .eq('user_id', userId)
        .eq('food_id', foodId)
        .limit(1)
        .maybeSingle();
    return row != null;
  }

  /// Kullanıcının favori `food_id` kümesi — **tek sorguda**, favori listede
  /// görünen öğeler için N+1 `isFavorite` çağrısı yapmayı önler.
  Future<Set<String>> favoriteIds(String userId) async {
    final rows = await _client
        .from(favoriteTable)
        .select('food_id')
        .eq('user_id', userId);
    return <String>{
      for (final row in rows as List)
        if ((row as Map<String, dynamic>)['food_id'] != null)
          (row['food_id'] as Object).toString(),
    };
  }

  /// Kullanıcının favorileri — `favorite_foods` ⋈ `foods` ⋈ `food_nutrition`.
  ///
  /// ## 200 kayıt sınırı neden korunuyor?
  ///
  /// Eski türetilmiş liste son **200 öğünü** tarayıp frekans sayıyordu (web
  /// `useFavoriteFoods` parity). Tabloya geçerken bu tarama penceresi
  /// **kaybolmadı**: `favorite_foods` tekilleştirilmiş bir tablo olduğu için
  /// pratikte sınırsızdır, ama RLS + tablo boyutu denetlenebilir olsun diye
  /// `favoriteScanLimit = 200` kayıtla sınırlanır. Daha fazlası olan
  /// kullanıcıda en eski favoriler listede görünmez — bu, türetilmiş
  /// listenin zaten taşıdığı sınırın **aynısıdır** (web parity) ve liste
  /// 10 öğeyle kesildiği için pratikte fark edilmez.
  static const favoriteScanLimit = 200;

  /// Listede gösterilecek favori sayısı (eski türetilmiş liste de 10 idi).
  static const favoriteDisplayLimit = 10;

  Future<List<FoodItem>> favorites(String userId) async {
    final rows = await _client
        .from(favoriteTable)
        .select(
          'food_id, created_at, '
          'foods(id, name, brand, serving_size_g, '
          'food_nutrition(kcal, protein_g, carbs_g, fat_g))',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(favoriteScanLimit);

    final items = <FoodItem>[];
    for (final row in rows) {
      // FK `NOT NULL` + `ON DELETE CASCADE` ⇒ join hep dolu; yine de
      // savunma-derinliği: RLS/join gevşerse **yarım gıda** (0 kcal) liste
      // satırı olarak düşmesin.
      final item = _favoriteToItem(Map<String, dynamic>.from(row));
      if (item == null) continue;
      items.add(item);
      if (items.length >= favoriteDisplayLimit) break;
    }
    return items;
  }

  /// `foods` tablosunda **`deleted_at` kolonu yoktur** (`full_setup.sql:70-80`)
  /// ve `FoodRepository` hiçbir yerde `.delete()` çağırmaz — yani gıda
  /// silme yolu fiziksel silmedir ve istemci süzgeci gerekmez.
  /// `meal_entries` tarafındaki üç sorgu ise `deleted_at IS NULL` gönderir
  /// (sunucu süzgeci) ve dönen satırlar istemcide de elenir — aynı savunma
  /// derinliği burada da uygulanır: süzgeç **kaybolsa** bile silinmiş bir
  /// öğün favorilerde/son yenilenlerde "yemek önerisi" olarak görünmez.
  ///
  /// Sorgular `meal_entries`'ten yalnız gıda adı için yararlanır; `deleted_at`
  /// kolonu `select()` listesine **açıkça eklenir** çünkü istemci elemesi
  /// ancak kolon geldiyse mümkündür (analytics/fetchDaily ile aynı desen).
  static bool _isDeleted(Map<String, dynamic> row) {
    final v = row['deleted_at'];
    if (v == null) return false;
    if (v is String) return v.isNotEmpty;
    return true;
  }

  /// Gıda silindiğinde favorileri temizler.
  ///
  /// ## Neden bu yol `favorite_foods`'ta gerekli olmasa da var?
  ///
  /// `favorite_foods.food_id` FK'si `ON DELETE CASCADE`
  /// (`full_setup.sql:188`) — yani gıda fiziksel silinince favori satırı
  /// **zaten** Postgres tarafından silinir ve **ölü `food_id` kalmaz**. Bu
  /// metot, o güvenceye ek olarak (a) temizlemenin **ne zaman** yapıldığını
  /// açık eder, (b) `ON CONFLICT` upsert'inin yarış koşulunda yarım
  /// kaldığı senaryoyu kapatır ve (c) yedek **dışa aktarımının**
  /// `foods` silinmiş ama favori satırı kalmışsa ölü `food_id` yazmasını
  /// engeller (A2r5'in `food_id` eşleşme kararı: eşleşmeyen kayıt
  /// atlanır, `StateError` ile tüm import'u düşürmek yerine).
  ///
  /// RLS: `favorite_foods` DELETE politikası `auth.uid() = user_id`
  /// (`full_setup.sql:333`) — yalnızca kendi satırı silinir.
  Future<void> removeFavoritesForFood(String userId, String foodId) =>
      removeFavorite(userId, foodId);

  /// Kullanıcının **kendi eklediği** gıdayı siler ve favorileri temizler.
  ///
  /// ## Sıralama neden önemli?
  ///
  /// `foods` silinmeden **önce** favori satırı açıkça silinir. FK
  /// `ON DELETE CASCADE` olsaydı bu gereksiz olurdu; ama:
  ///
  /// 1. `meal_entries.food_id` FK'si `ON DELETE` **tanımsız** (yani
  ///    `NO ACTION`, `full_setup.sql:135`) → gıdayı kullanan bir öğün varsa
  ///    silme `23503` ile **reddedilir**. Favoriler önce silinerek kullanıcıya
  ///    "favoriler silindi ama gıda silinemedi" gibi yarım bir sonuç
  ///    gösterilmemeli; bu yüzden önce **gıda silinir**, hata alırsa favori
  ///    satırlarına **dokunulmaz**.
  /// 2. Silme başarılıysa favori satırları (CASCADE zaten silmiş olsa da)
  ///    **idempotent** olarak temizlenir → `written` defteri tutarlı kalır.
  ///
  /// RLS: `foods` DELETE politikası `created_by = auth.uid()`
  /// (`full_setup.sql:287`) — yalnızca kendi gıdası silinebilir; başkasının
  /// gıdası `0` satır siler ve `false` döner (sessiz "başarı" olmaz).
  Future<bool> deleteFood(String userId, String foodId) async {
    final removed = await _client
        .from('foods')
        .delete()
        .eq('id', foodId)
        .eq('created_by', userId)
        .select('id');
    if (removed.isEmpty) return false;
    // Gıda gerçekten silindi → favori satırı (CASCADE sonrası) yok.
    await removeFavoritesForFood(userId, foodId);
    return true;
  }

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
        .select(
          'id, name, brand, serving_size_g, '
          'food_nutrition(kcal, protein_g, carbs_g, fat_g)',
        )
        .ilike('name', '%$q%')
        .order('popularity_count', ascending: false)
        .limit(10);

    for (final row in dbFoods) {
      final nutrition = _firstNutrition(row['food_nutrition']);
      if (nutrition == null) continue;
      final name = row['name'] as String;
      final key = name.toLowerCase();
      if (!seenNames.add(key)) continue;
      results.add(
        FoodItem(
          id: row['id'] as String,
          foodId: row['id'] as String,
          name: name,
          brand: row['brand'] as String?,
          servingSizeG: (row['serving_size_g'] as num?)?.toDouble(),
          calories: (nutrition['kcal'] as num).toDouble(),
          proteinG: (nutrition['protein_g'] as num).toDouble(),
          carbsG: (nutrition['carbs_g'] as num).toDouble(),
          fatG: (nutrition['fat_g'] as num).toDouble(),
        ),
      );
    }

    // 2) Kullanıcının custom (manuel) girdileri — 100g'a normalize
    final customFoods = await _client
        .from('meal_entries')
        .select(
          'id, custom_name, amount_g_ml, calculated_kcal, '
          'calculated_protein, calculated_carbs, calculated_fat, food_id, '
          'deleted_at',
        )
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .isFilter('food_id', null)
        .ilike('custom_name', '%$q%')
        .order('created_at', ascending: false)
        .limit(50);

    for (final row in customFoods) {
      // İkinci savunma katmanı: sunucu süzgeci bir gün gevşerse silinmiş bir
      // öğün arama sonucunda "yeniden eklenebilir yemek" olarak görünür.
      if (_isDeleted(Map<String, dynamic>.from(row))) continue;
      final customName = row['custom_name'] as String?;
      if (customName == null || customName.isEmpty) continue;
      final key = customName.toLowerCase();
      if (!seenNames.add(key)) continue;
      results.add(customItem(row, idPrefix: 'custom_'));
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
  /// sayımı (web `useFavoriteFoods` parity, **türetilmiş** — tabloya yazmaz;
  /// "favori" ≠ "en çok yenilen" olduğu için [favorites] ile ayrıdır).
  Future<List<FoodItem>> frequentFoods(String userId) async {
    final rows = await _client
        .from('meal_entries')
        .select(
          'id, food_id, custom_name, amount_g_ml, calculated_kcal, '
          'calculated_protein, calculated_carbs, calculated_fat, deleted_at, '
          'foods(id, name, brand, serving_size_g, '
          'food_nutrition(kcal, protein_g, carbs_g, fat_g))',
        )
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(200);

    // isim(küçük harf) → {count, row} — ilk görülen row tutulur
    final counts = <String, int>{};
    final firstRow = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      if (_isDeleted(Map<String, dynamic>.from(row))) continue;
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
        .select(
          'id, food_id, custom_name, amount_g_ml, calculated_kcal, '
          'calculated_protein, calculated_carbs, calculated_fat, created_at, '
          'deleted_at, '
          'foods(id, name, brand, serving_size_g, '
          'food_nutrition(kcal, protein_g, carbs_g, fat_g))',
        )
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(50);

    final seen = <String>{};
    final items = <FoodItem>[];
    for (final row in rows) {
      if (_isDeleted(Map<String, dynamic>.from(row))) continue;
      final name = _rowName(row);
      if (!seen.add(name.toLowerCase())) continue;
      items.add(_rowToItem(row, lastUsedAt: row['created_at'] as String?));
      if (items.length >= 10) break;
    }
    return items;
  }

  // --- yardımcılar -------------------------------------------------------

  /// `favorite_foods` satırını `FoodItem`'e çevirir.
  ///
  /// Besin (nutrition) satırı **yoksa** `null` döner: `foods` tablosunda
  /// `food_nutrition` satırı olmayan bir gıda arama sonuçlarında da elenir
  /// (`search`'te `nutrition == null → continue`), favori listesinde aynı
  /// kural geçerli — aksi halde listede **0 kcal** satırlar görünür ve
  /// kullanıcı yemeği ekleyince hesap hatası alır.
  static FoodItem? _favoriteToItem(Map<String, dynamic> row) {
    final foods = row['foods'];
    final foodId = row['food_id'] as String?;
    if (foodId == null || foods is! Map<String, dynamic>) return null;
    final nutrition = _firstNutrition(foods['food_nutrition']);
    if (nutrition == null) return null;
    return FoodItem(
      id: foodId,
      foodId: foodId,
      name: foods['name'] as String? ?? 'Bilinmeyen',
      brand: foods['brand'] as String?,
      servingSizeG: (foods['serving_size_g'] as num?)?.toDouble(),
      calories: (nutrition['kcal'] as num?)?.toDouble() ?? 0,
      proteinG: (nutrition['protein_g'] as num?)?.toDouble() ?? 0,
      carbsG: (nutrition['carbs_g'] as num?)?.toDouble() ?? 0,
      fatG: (nutrition['fat_g'] as num?)?.toDouble() ?? 0,
    );
  }

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
    return customItem(row, useCount: useCount, lastUsedAt: lastUsedAt);
  }

  /// Custom (food_id IS NULL) girdiyi 100g başına değerlere çevirir.
  /// Web formülü: kcal round(x/amount*100), makrolar round1(x/amount*100),
  /// amount = amount_g_ml ?? 100.
  ///
  /// `amount <= 0` (null ya da bozuk/negatif satır) durumunda web'in
  /// `x/0` davranışı `Infinity` üretir ve Dart'ta `Infinity.round()`
  /// **istisna fırlatır** (`Unsupported operation: Infinity or NaN toInt`) →
  /// favoriler/son-yenilenler listesi tamamen çöker. Bu yolda 100g
  /// varsayılır (miktar bilinmiyorsa 100g'a normalize etmek web'in
  /// `?? 100` varsayılanıyla aynı mantıktır).
  static FoodItem customItem(
    Map<String, dynamic> row, {
    String idPrefix = '',
    int? useCount,
    String? lastUsedAt,
  }) {
    final rawAmount = (row['amount_g_ml'] as num?)?.toDouble() ?? 100;
    final amount = (rawAmount.isNaN || rawAmount <= 0) ? 100.0 : rawAmount;
    double per100(String column) {
      final raw = (row[column] as num?)?.toDouble() ?? 0;
      final value = raw / amount * 100;
      // Infinity/NaN normalizasyonu yine patlatmasın.
      return value.isFinite ? value : 0;
    }

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
final foodSearchProvider = FutureProvider.autoDispose
    .family<List<FoodItem>, String>((ref, query) {
      final user = ref.watch(currentUserProvider);
      if (user == null || query.trim().length < 2) return const [];
      return ref.watch(foodRepositoryProvider).search(user.id, query);
    });

/// Kullanıcının **seçtiği** favoriler (`favorite_foods` tablosu).
///
/// A4r7 (ürün kararı 1-A) ile tabloya geçirildi. `200` kayıtlık tarama
/// penceresi [FoodRepository.favoriteScanLimit] altında **korunur** (web
/// parity); geri yüklenen favoriler artık **görünür** (A2r5'in import'u
/// yazıyordu ama hiçbir okuma yolu yoktu).
final favoriteFoodsProvider = FutureProvider<List<FoodItem>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(foodRepositoryProvider).favorites(user.id);
});

/// Favorilerin **`food_id` kümesi** — favori yıldızının dolu/boş durumunu
/// tek sorguda öğrenmek için. Arama sonuçlarındaki her satır için ayrı
/// `isFavorite` çağırmak N+1 olurdu; bu provider hepsini birden çözer.
final favoriteIdsProvider = FutureProvider<Set<String>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const <String>{};
  return ref.watch(foodRepositoryProvider).favoriteIds(user.id);
});

/// En sık yenilenler (**türetilmiş** — `favorite_foods`'a yazmaz).
///
/// Eski `favoriteFoodsProvider`'ın yerini alan bu liste, "favori" değil
/// "en çok yediğim" anlamını taşır ve ayrı bir bölümde gösterilir.
final frequentFoodsProvider = FutureProvider<List<FoodItem>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(foodRepositoryProvider).frequentFoods(user.id);
});

/// Son yenilenler (web `useRecentFoods`).
final recentFoodsProvider = FutureProvider<List<FoodItem>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return const [];
  return ref.watch(foodRepositoryProvider).recents(user.id);
});
