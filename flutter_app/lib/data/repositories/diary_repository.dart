import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../models/meal_entry.dart';
import '../models/water_entry.dart';
import '../models/weight_entry.dart';
import '../supabase/supabase_client_provider.dart';
import 'auth_repository.dart';

/// Tarihi web `format(date, 'yyyy-MM-dd')` ile aynı biçimde yazar.
String formatEntryDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Günün yemek toplamları — web `useDailyData.totals` karşılığı.
typedef DailyTotals = ({
  double calories,
  double protein,
  double carbs,
  double fat,
});

/// Seçili günün tüm günlük verisi (web `useDailyData` dönüş değeri).
class DailyData {
  const DailyData({
    required this.mealEntries,
    required this.waterEntries,
    this.latestWeight,
  });

  final List<MealEntry> mealEntries;
  final List<WaterEntry> waterEntries;

  /// Tarihten bağımsız en son kilo kaydı (web parity — gün filtresi YOK).
  final WeightEntry? latestWeight;

  /// Öğün tipine göre gruplandırma (web `mealsByType`).
  Map<MealType, List<MealEntry>> get mealsByType {
    final map = <MealType, List<MealEntry>>{};
    for (final entry in mealEntries) {
      final type = MealType.values.asNameMap()[entry.mealType];
      if (type == null) continue;
      map.putIfAbsent(type, () => []).add(entry);
    }
    return map;
  }

  /// Gün toplamları — web `totals` reduce'i ile aynı.
  DailyTotals get totals {
    var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0;
    for (final e in mealEntries) {
      calories += e.calculatedKcal;
      protein += e.calculatedProtein;
      carbs += e.calculatedCarbs;
      fat += e.calculatedFat;
    }
    return (calories: calories, protein: protein, carbs: carbs, fat: fat);
  }

  /// Toplam su (ml) — web `totalWater`.
  double get totalWater =>
      waterEntries.fold(0.0, (sum, e) => sum + e.amountMl);

  static const empty = DailyData(mealEntries: [], waterEntries: []);
}

/// Günlük (diary) CRUD — web `useDailyData.ts` karşılığı.
///
/// Tüm sorgular `entry_date = yyyy-MM-dd` + `deleted_at IS NULL`
/// filtreleriyle; silme soft-delete (`deleted_at = now()`).
class DiaryRepository {
  DiaryRepository(this._client);

  final SupabaseClient _client;

  /// `timestamptz` kolonlarına yazılan damga daima **UTC** olmalı.
  ///
  /// `DateTime.now()` yerel saati (UTC kaydı) döndürür; `+03:00` ofseti olan
  /// bir istemcide bu, sunucu tarafında ~3 saat ileri bir zaman damgası
  /// olarak yorumlanır. Web `new Date().toISOString()` UTC ürettiği için
  /// burada da `.toUtc()` zorunlu.
  String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// NaN / Infinity / negatif değerleri yazmadan reddeder.
  static void _requireFiniteNonNegative(String name, double v) {
    if (v.isNaN || v.isInfinite || v < 0) {
      throw ArgumentError.value(v, name, 'NaN, Infinity veya negatif olamaz');
    }
  }

  /// Miktar alanları için ayrıca `> 0` zorunlu (0'a bölme riski).
  static void _requireFinitePositive(String name, double v) {
    if (v.isNaN || v.isInfinite || v <= 0) {
      throw ArgumentError.value(v, name, 'NaN, Infinity veya sıfırdan küçük olamaz');
    }
  }

  /// Seçili günün tüm verisi: öğünler (created_at asc), su (entry_time asc)
  /// ve en son kilo kaydı (tarih filtresiz, entry_date desc limit 1).
  Future<DailyData> fetchDaily(String userId, DateTime date) async {
    final dateStr = formatEntryDate(date);

    final mealsFuture = _client
        .from('meal_entries')
        .select()
        .eq('user_id', userId)
        .eq('entry_date', dateStr)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: true);

    final waterFuture = _client
        .from('water_entries')
        .select()
        .eq('user_id', userId)
        .eq('entry_date', dateStr)
        .isFilter('deleted_at', null)
        .order('entry_time', ascending: true);

    final weightFuture = _client
        .from('weight_entries')
        .select()
        .eq('user_id', userId)
        .isFilter('deleted_at', null)
        .order('entry_date', ascending: false)
        .limit(1)
        .maybeSingle();

    final results =
        await Future.wait<dynamic>([mealsFuture, waterFuture, weightFuture]);

    return DailyData(
      mealEntries: (results[0] as List)
          .map((r) => MealEntry.fromJson(r as Map<String, dynamic>))
          .toList(),
      waterEntries: (results[1] as List)
          .map((r) => WaterEntry.fromJson(r as Map<String, dynamic>))
          .toList(),
      latestWeight: results[2] == null
          ? null
          : WeightEntry.fromJson(results[2] as Map<String, dynamic>),
    );
  }

  /// Yemek girdisi ekle (web `addMealEntry` — payload alanları aynı).
  Future<MealEntry> addMealEntry(
    String userId, {
    required String mealType,
    required double amountGMl,
    required double calculatedKcal,
    required double calculatedProtein,
    required double calculatedCarbs,
    required double calculatedFat,
    required String entryDate,
    String source = 'manual',
    String? foodId,
    String? customName,
    String? note,
    String? photoUrl,
  }) async {
    // Yazma sınırı doğrulaması: `NaN`/`Infinity` Postgres'e JSON olarak
    // gider ve `numeric` kolonlarında hata/istisna üretir; negatif ya da
    // sıfır miktar ise 100g normalizasyonunu (`x/amount*100`) bozar ve
    // tüm gün toplamlarını yanlışlaştırır.
    _requireFinitePositive('amountGMl', amountGMl);
    _requireFiniteNonNegative('calculatedKcal', calculatedKcal);
    _requireFiniteNonNegative('calculatedProtein', calculatedProtein);
    _requireFiniteNonNegative('calculatedCarbs', calculatedCarbs);
    _requireFiniteNonNegative('calculatedFat', calculatedFat);

    final data = await _client
        .from('meal_entries')
        .insert({
          'user_id': userId,
          'food_id': foodId,
          'custom_name': customName,
          'meal_type': mealType,
          'amount_g_ml': amountGMl,
          'calculated_kcal': calculatedKcal,
          'calculated_protein': calculatedProtein,
          'calculated_carbs': calculatedCarbs,
          'calculated_fat': calculatedFat,
          'entry_date': entryDate,
          'note': note,
          'photo_url': photoUrl,
          'source': source,
        })
        .select()
        .single();
    return MealEntry.fromJson(data);
  }

  /// Yemek girdisi güncelle (web `updateMealEntry` — updated_at damgalı).
  ///
  /// [userId] hem `eq('id', ...)` hem de `eq('user_id', ...)` filtresine
  /// eklenir: RLS zaten `auth.uid() = user_id` ile koruyor, ama istemci
  /// tarafında ikinci filtre **kırık/eksik yetki** durumunda (örn. RLS
  /// politikası yanlışlıkla gevşetilirse) başkasının kaydının sessizce
  /// ezilmesini imkânsız kılar. Kullanıcının oturumu dışındaki bir id
  /// geçilirse `.single()` 0 satır döner ve `PostgrestException` fırlatır —
  /// sessiz veri kaybı yerine yüzeye çıkan hata.
  Future<MealEntry> updateMealEntry(
    String userId,
    String id,
    Map<String, dynamic> updates,
  ) async {
    // Kısmi güncelleme: `updates` yalnızca verilen alanları içerir, diğer
    // alanlar (source/food_id/photo_url/entry_date) korunur. Yazılan sayısal
    // alanlar yine de doğrulanır — UI `_parse` boş metni 0'a çevirdiği
    // için 0 miktar buradan geçebilirdi.
    final amount = updates['amount_g_ml'];
    if (amount is double) _requireFinitePositive('amount_g_ml', amount);
    for (final key in const [
      'calculated_kcal',
      'calculated_protein',
      'calculated_carbs',
      'calculated_fat',
    ]) {
      final v = updates[key];
      if (v is double) _requireFiniteNonNegative(key, v);
    }

    final data = await _client
        .from('meal_entries')
        .update({...updates, 'updated_at': _nowIso()})
        .eq('id', id)
        .eq('user_id', userId)
        .select()
        .single();
    return MealEntry.fromJson(data);
  }

  /// Yemek girdisi sil — soft delete (web parity).
  ///
  /// [userId] kapsam filtresi — bkz. [updateMealEntry].
  Future<void> deleteMealEntry(String userId, String id) async {
    await _client
        .from('meal_entries')
        .update({'deleted_at': _nowIso()})
        .eq('id', id)
        .eq('user_id', userId);
  }

  /// Yemek girdisini geri al — `deleted_at = null` (soft-delete undo).
  /// Dashboard kaydır-sil sonrası "Geri Al" SnackBar aksiyonu.
  ///
  /// [userId] kapsam filtresi — bkz. [updateMealEntry].
  Future<void> restoreMealEntry(String userId, String id) async {
    await _client
        .from('meal_entries')
        .update({'deleted_at': null, 'updated_at': _nowIso()})
        .eq('id', id)
        .eq('user_id', userId);
  }

  /// Su ekle (web `addWaterEntry` — entry_time DB default'una bırakılır).
  ///
  /// `water_entries.amount_ml` DB sütunu `integer`. Dart tarafı ml'yi
  /// `double` tutar (UI ilerleme çubuğu bölmesi için) ama PostgREST'e
  /// `250.0` gönderilirse Postgres integer ayrıştırıcısı ondalık noktayı
  /// reddeder → `22P02 invalid input syntax for type integer: "250.0"` →
  /// POST 400. Bu yüzden insert'te `int`'e dönüştürülür (su ml her zaman
  /// tam sayıdır; okuma yolu json_serializable'ın int→double zorlamasıyla
  /// zararsız çalışır).
  Future<WaterEntry> addWaterEntry(
    String userId, {
    required double amountMl,
    required String entryDate,
  }) async {
    if (amountMl.isNaN || amountMl.isInfinite || amountMl <= 0) {
      throw ArgumentError.value(
        amountMl,
        'amountMl',
        'Su miktarı NaN, Infinity veya sıfırdan küçük olamaz',
      );
    }
    final data = await _client
        .from('water_entries')
        .insert({
          'user_id': userId,
          'amount_ml': amountMl.round(),
          'entry_date': entryDate,
        })
        .select()
        .single();
    return WaterEntry.fromJson(data);
  }

  /// Su kaydı sil — soft delete (web'de yok ama tutarlılık için aynı desen).
  ///
  /// [userId] kapsam filtresi — bkz. [updateMealEntry].
  Future<void> deleteWaterEntry(String userId, String id) async {
    await _client
        .from('water_entries')
        .update({'deleted_at': _nowIso()})
        .eq('id', id)
        .eq('user_id', userId);
  }

  /// Kilo kaydı ekle (web `addWeightEntry`).
  Future<WeightEntry> addWeightEntry(
    String userId, {
    required double weightKg,
    required String entryDate,
    String? note,
  }) async {
    if (weightKg.isNaN || weightKg.isInfinite || weightKg <= 0) {
      // `weight_entries.weight_kg` NOT NULL + domain anlamı: 0/negatif
      // kayıt BMI ve tüm makro hedeflerini bozacağı için DB'ye hiç
      // gönderilmez. Çağıran (weight_card) zaten `weight <= 0` filtresi
      // uyguluyor; buradaki kontrol o filtrenin atlandığı her yol için
      // son savunmadır ve hatayı yüzeye taşır.
      throw ArgumentError.value(
        weightKg,
        'weightKg',
        'Kilo 0, negatif, NaN veya Infinity olamaz',
      );
    }

    final data = await _client
        .from('weight_entries')
        .insert({
          'user_id': userId,
          'weight_kg': weightKg,
          'entry_date': entryDate,
          'note': note,
        })
        .select()
        .single();
    return WeightEntry.fromJson(data);
  }
}

final diaryRepositoryProvider = Provider<DiaryRepository>((ref) {
  return DiaryRepository(ref.watch(supabaseClientProvider));
});

/// Dashboard'da seçili gün — sadece tarih kısmı anlamlı.
final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// Seçili günün tüm verisi (web `useDailyData(date)` karşılığı).
/// Ekleme/silme sonrası `ref.invalidate(dailyDataProvider)` ile tazelenir.
final dailyDataProvider = FutureProvider<DailyData>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return DailyData.empty;
  final date = ref.watch(selectedDateProvider);
  return ref.watch(diaryRepositoryProvider).fetchDaily(user.id, date);
});
