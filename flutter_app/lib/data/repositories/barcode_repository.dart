import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/barcode_food.dart';
import '../supabase/supabase_client_provider.dart';

/// Barkod akışı — web `BarcodeScanDialog.tsx` lookup + create parity.
///
///  - [lookupByBarcode]: `foods` tablosunda `barcode = code` araması
///    (`food_nutrition` join ile). Bulunursa [BarcodeFood] (`fromDb: true`),
///    yoksa `null`.
///  - [createFoodWithNutrition]: DB'de olmayan ürün için önce `foods` satırı
///    (barcode, source, created_by) sonra `food_nutrition` satırı oluşturur.
///    Oluşturulan `food_id`'yi döndürür (kayıt sırasında `meal_entries.food_id`
///    olarak kullanılır).
class BarcodeRepository {
  BarcodeRepository(this._client);

  final SupabaseClient _client;

  /// Barkodu DB'de arar. Bulunamazsa `null` döner (çağıran katman AI'a düşer).
  Future<BarcodeFood?> lookupByBarcode(String code) async {
    final row = await _client
        .from('foods')
        .select('id, name, brand, barcode, serving_size_g, '
            'food_nutrition(kcal, protein_g, carbs_g, fat_g, fiber_g, '
            'sugar_g, salt_g, saturated_fat_g, trans_fat_g, '
            'nova_score, nutri_score)')
        .eq('barcode', code)
        .maybeSingle();

    if (row == null) return null;
    final food = BarcodeFood.fromDbRow(row);
    // nutrition join'i boşsa DB yemeği sayılmaz (web: `food && food_nutrition`).
    if (food.calories == 0 &&
        food.proteinG == 0 &&
        food.carbsG == 0 &&
        food.fatG == 0) {
      return null;
    }
    return food;
  }

  /// Yeni bir `foods` + `food_nutrition` satırı oluşturur ve `food_id` döndürür.
  /// Yalnızca DB'de bulunmayan (`fromDb: false`) ve barkodu olan ürünler için
  /// çağrılır. [source] — `"photo"` (foto ile tanındıysa) veya `"barcode"`.
  Future<String> createFoodWithNutrition({
    required String userId,
    required BarcodeFood food,
    required String source,
  }) async {
    final newFood = await _client
        .from('foods')
        .insert({
          'name': food.name,
          'brand': food.brand,
          'barcode': food.barcode,
          'serving_size_g': food.servingSizeG ?? food.amountGMl,
          'source': source,
          'created_by': userId,
        })
        .select('id')
        .single();

    final foodId = newFood['id'] as String;

    await _client.from('food_nutrition').insert({
      'food_id': foodId,
      'kcal': food.calories,
      'protein_g': food.proteinG,
      'carbs_g': food.carbsG,
      'fat_g': food.fatG,
      'fiber_g': food.fiberG,
      'sugar_g': food.sugarsG, // DB sütunu: sugar_g (tekil)
      'salt_g': food.saltG,
      'saturated_fat_g': food.saturatedFatG,
      'trans_fat_g': food.transFatG,
      'nova_score': food.novaScore,
      'nutri_score': food.nutriScore,
    });

    return foodId;
  }
}

final barcodeRepositoryProvider = Provider<BarcodeRepository>((ref) {
  return BarcodeRepository(ref.watch(supabaseClientProvider));
});
