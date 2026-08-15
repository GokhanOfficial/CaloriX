import 'package:calorix/data/models/barcode_food.dart';
import 'package:flutter_test/flutter_test.dart';

/// BarcodeFood modelinin saf (Supabase'siz) hesapları ve fromJson/DB
/// eşlemeleri — web `BarcodeScanDialog` `FoodData` parity referansı.
void main() {
  group('BarcodeFood.fromAiFood', () {
    test('yeni alan adları doğru eşleşir, barcode aktarılır', () {
      final f = BarcodeFood.fromAiFood({
        'name': 'Bisküvi',
        'amount_g_ml': 30,
        'calories_per_100g': 480,
        'protein_g_per_100g': 6,
        'carbs_g_per_100g': 65,
        'fat_g_per_100g': 22,
        'saturated_fat_g_per_100g': 9,
        'trans_fat_g_per_100g': 0.2,
        'sugars_g_per_100g': 35,
        'fiber_g_per_100g': 3,
        'salt_g_per_100g': 1.1,
        'nova_score': 4,
        'nutri_score': 'e',
        'confidence': 80,
      }, '8690001');
      expect(f.name, 'Bisküvi');
      expect(f.barcode, '8690001');
      expect(f.amountGMl, 30);
      expect(f.calories, 480);
      expect(f.proteinG, 6);
      expect(f.carbsG, 65);
      expect(f.fatG, 22);
      expect(f.saturatedFatG, 9);
      expect(f.transFatG, 0.2);
      expect(f.sugarsG, 35);
      expect(f.fiberG, 3);
      expect(f.saltG, 1.1);
      expect(f.novaScore, 4);
      expect(f.nutriScore, 'E'); // uppercase
      expect(f.confidence, 80);
      expect(f.fromDb, isFalse);
    });

    test('eski kısaltma alanları tolere edilir (legacy parity)', () {
      final f = BarcodeFood.fromAiFood({
        'name': 'Kola',
        'amount_g_ml': 250,
        'calories': 42,
        'protein_g': 0,
        'carbs_g': 10.6,
        'fat_g': 0,
      }, null);
      expect(f.calories, 42);
      expect(f.carbsG, 10.6);
      expect(f.barcode, isNull);
    });

    test('yeni alan eski alana öncelikli', () {
      final f = BarcodeFood.fromAiFood({
        'name': 'X',
        'calories_per_100g': 100,
        'calories': 999,
      }, null);
      expect(f.calories, 100);
    });

    test('amount 0/eksikse 100 olur (web `|| 100`)', () {
      expect(BarcodeFood.fromAiFood({'name': 'A'}, null).amountGMl, 100);
      expect(BarcodeFood.fromAiFood({'name': 'A', 'amount_g_ml': 0}, null).amountGMl, 100);
    });

    test('name eksikse boş string', () {
      expect(BarcodeFood.fromAiFood({}, '123').name, '');
    });

    test('nova_score num olarak gelse int olur', () {
      expect(BarcodeFood.fromAiFood({'name': 'Y', 'nova_score': 3.0}, null).novaScore, 3);
    });
  });

  group('BarcodeFood.fromDbRow', () {
    test('nutrition Map join (PostgREST 1:1) doğru eşleşir, fromDb true', () {
      final f = BarcodeFood.fromDbRow({
        'id': 'food-uuid',
        'name': 'Ekmek',
        'brand': 'MarkaX',
        'barcode': '123456789',
        'serving_size_g': 50,
        'food_nutrition': {
          'kcal': 265,
          'protein_g': 9,
          'carbs_g': 49,
          'fat_g': 3.2,
          'fiber_g': 4,
          'sugar_g': 5, // DB sütunu tekil
          'salt_g': 1.2,
          'saturated_fat_g': 0.7,
          'trans_fat_g': 0,
          'nova_score': 3,
          'nutri_score': 'c',
        },
      });
      expect(f.fromDb, isTrue);
      expect(f.foodId, 'food-uuid');
      expect(f.name, 'Ekmek');
      expect(f.brand, 'MarkaX');
      expect(f.barcode, '123456789');
      expect(f.servingSizeG, 50);
      expect(f.amountGMl, 50); // serving_size_g'den
      expect(f.calories, 265);
      expect(f.fatG, 3.2);
      expect(f.sugarsG, 5);
      expect(f.nutriScore, 'C');
    });

    test('nutrition tek elemanlı List döndüğünde de çalışır', () {
      final f = BarcodeFood.fromDbRow({
        'id': 'u',
        'name': 'Süt',
        'food_nutrition': [
          {'kcal': 60, 'protein_g': 3, 'carbs_g': 5, 'fat_g': 3.2},
        ],
      });
      expect(f.calories, 60);
      expect(f.fatG, 3.2);
      expect(f.fromDb, isTrue);
    });

    test('nutrition yoksa makrolar 0, fromDb true (çağıran null sayar)', () {
      final f = BarcodeFood.fromDbRow({
        'id': 'u',
        'name': 'Bozuk',
        'food_nutrition': null,
      });
      expect(f.calories, 0);
      expect(f.proteinG, 0);
      expect(f.fromDb, isTrue); // row var ama nutrition boş
    });
  });

  group('BarcodeFood.forAmount', () {
    test('kcal yuvarlanır, makrolar 1 ondalık (web parity)', () {
      final f = BarcodeFood(
        name: 'A',
        amountGMl: 100,
        calories: 250,
        proteinG: 20,
        carbsG: 5.5,
        fatG: 18,
      );
      final v = f.forAmount(200);
      expect(v.kcal, 500);
      expect(v.protein, 40.0);
      expect(v.carbs, 11.0);
      expect(v.fat, 36.0);
    });

    test('kesirli miktar doğru yuvarlanır', () {
      final f = BarcodeFood(
        name: 'A',
        amountGMl: 100,
        calories: 100,
        proteinG: 10,
        carbsG: 10,
        fatG: 10,
      );
      final v = f.forAmount(33);
      expect(v.kcal, 33);
      expect(v.protein, 3.3);
    });
  });

  group('BarcodeFood.displayName', () {
    test('brand varsa "name (brand)"', () {
      final f = BarcodeFood(
        name: 'Yoğurt',
        amountGMl: 100,
        calories: 60,
        proteinG: 3,
        carbsG: 5,
        fatG: 3,
        brand: 'Sütaş',
      );
      expect(f.displayName, 'Yoğurt (Sütaş)');
    });

    test('brand yoksa sadece name', () {
      final f = BarcodeFood(
        name: 'Elma',
        amountGMl: 100,
        calories: 52,
        proteinG: 0.3,
        carbsG: 14,
        fatG: 0.2,
      );
      expect(f.displayName, 'Elma');
    });

    test('brand boş stringse name döner', () {
      final f = BarcodeFood(
        name: 'Elma',
        amountGMl: 100,
        calories: 52,
        proteinG: 0.3,
        carbsG: 14,
        fatG: 0.2,
        brand: '',
      );
      expect(f.displayName, 'Elma');
    });
  });
}
