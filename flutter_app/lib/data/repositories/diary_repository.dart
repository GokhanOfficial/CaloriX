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

  String _nowIso() => DateTime.now().toIso8601String();

  /// Seçili günün tüm verisi: öğünler (created_at asc), su (entry_time asc)
  /// ve en son kilo kaydı (tarih filtresiz, entry_date desc limit 1).
  Future<DailyData> fetchDaily(String userId, DateTime date) async {
    final dateStr = formatEntryDate(date);

    final mealsFuture = _client
        .from('meal_entries')
        .select()
        .eq('user_id', userId)
        .eq('entry_date', dateStr)
        .filter('deleted_at', 'is', null)
        .order('created_at', ascending: true);

    final waterFuture = _client
        .from('water_entries')
        .select()
        .eq('user_id', userId)
        .eq('entry_date', dateStr)
        .filter('deleted_at', 'is', null)
        .order('entry_time', ascending: true);

    final weightFuture = _client
        .from('weight_entries')
        .select()
        .eq('user_id', userId)
        .filter('deleted_at', 'is', null)
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
  Future<MealEntry> updateMealEntry(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final data = await _client
        .from('meal_entries')
        .update({...updates, 'updated_at': _nowIso()})
        .eq('id', id)
        .select()
        .single();
    return MealEntry.fromJson(data);
  }

  /// Yemek girdisi sil — soft delete (web parity).
  Future<void> deleteMealEntry(String id) async {
    await _client
        .from('meal_entries')
        .update({'deleted_at': _nowIso()})
        .eq('id', id);
  }

  /// Su ekle (web `addWaterEntry` — entry_time DB default'una bırakılır).
  Future<WaterEntry> addWaterEntry(
    String userId, {
    required double amountMl,
    required String entryDate,
  }) async {
    final data = await _client
        .from('water_entries')
        .insert({
          'user_id': userId,
          'amount_ml': amountMl,
          'entry_date': entryDate,
        })
        .select()
        .single();
    return WaterEntry.fromJson(data);
  }

  /// Su kaydı sil — soft delete (web'de yok ama tutarlılık için aynı desen).
  Future<void> deleteWaterEntry(String id) async {
    await _client
        .from('water_entries')
        .update({'deleted_at': _nowIso()})
        .eq('id', id);
  }

  /// Kilo kaydı ekle (web `addWeightEntry`).
  Future<WeightEntry> addWeightEntry(
    String userId, {
    required double weightKg,
    required String entryDate,
    String? note,
  }) async {
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
