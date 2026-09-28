import 'package:calorix/data/models/recognized_food.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecognizedFood.fromJson', () {
    test('yeni alan adları doğru eşleşir', () {
      final f = RecognizedFood.fromJson({
        'name': 'Köfte',
        'amount_g_ml': 120,
        'calories_per_100g': 250,
        'protein_g_per_100g': 20,
        'carbs_g_per_100g': 5,
        'fat_g_per_100g': 18,
        'confidence': 92,
      });
      expect(f.name, 'Köfte');
      expect(f.amountGMl, 120);
      expect(f.caloriesPer100G, 250);
      expect(f.proteinGPer100G, 20);
      expect(f.carbsGPer100G, 5);
      expect(f.fatGPer100G, 18);
      expect(f.confidence, 92);
    });

    test('eski kısaltma alanları tolere edilir (legacy parity)', () {
      final f = RecognizedFood.fromJson({
        'name': 'Salata',
        'amount_g_ml': 200,
        'calories': 80,
        'protein_g': 3,
        'carbs_g': 10,
        'fat_g': 4,
      });
      expect(f.caloriesPer100G, 80);
      expect(f.proteinGPer100G, 3);
      expect(f.carbsGPer100G, 10);
      expect(f.fatGPer100G, 4);
    });

    test('yeni alan eski alana öncelikli (ikisi varsa yeni kazanır)', () {
      final f = RecognizedFood.fromJson({
        'name': 'X',
        'calories_per_100g': 100,
        'calories': 999,
      });
      expect(f.caloriesPer100G, 100);
    });

    test('eksik değerler defaultlara düşer (amount 100, makrolar 0)', () {
      final f = RecognizedFood.fromJson({'name': 'Boş'});
      expect(f.amountGMl, 100);
      expect(f.caloriesPer100G, 0);
      expect(f.proteinGPer100G, 0);
      expect(f.carbsGPer100G, 0);
      expect(f.fatGPer100G, 0);
      expect(f.name, 'Boş');
    });

    test('name null ise boş stringe düşer', () {
      final f = RecognizedFood.fromJson({});
      expect(f.name, '');
    });

    test('genişletilmiş besin + nova/nutri score eşleşir', () {
      final f = RecognizedFood.fromJson({
        'name': 'Atıştırmalık',
        'calories_per_100g': 100,
        'protein_g_per_100g': 2,
        'carbs_g_per_100g': 60,
        'fat_g_per_100g': 1,
        'saturated_fat_g_per_100g': 0.5,
        'trans_fat_g_per_100g': 0.1,
        'sugars_g_per_100g': 40,
        'fiber_g_per_100g': 2,
        'salt_g_per_100g': 0.3,
        'nova_score': 4,
        'nutri_score': 'e',
        'confidence': 55.5,
      });
      expect(f.saturatedFatGPer100G, 0.5);
      expect(f.transFatGPer100G, 0.1);
      expect(f.sugarsGPer100G, 40);
      expect(f.fiberGPer100G, 2);
      expect(f.saltGPer100G, 0.3);
      expect(f.novaScore, 4);
      expect(f.nutriScore, 'e');
      expect(f.confidence, 55.5);
    });

    test('nova_score num olarak gelse int olur', () {
      final f = RecognizedFood.fromJson({
        'name': 'Y',
        'nova_score': 3.0,
      });
      expect(f.novaScore, 3);
    });

    test('sonlu olmayan sayılar varsayılana düşer (NaN/Infinity patlatmaz)', () {
      // JSON'da `NaN` yazılamaz ama edge function `1e999` → `Infinity`
      // döndürebilir. Bu değer `forAmount()` içinde
      // `UnsupportedError` fırlatır ve tanıma ekranını çökertirdi.
      final f = RecognizedFood.fromJson({
        'name': 'Bozuk',
        'amount_g_ml': double.infinity,
        'calories_per_100g': double.infinity,
        'protein_g_per_100g': double.nan,
        'carbs_g_per_100g': double.negativeInfinity,
        'fat_g_per_100g': 12,
        'fiber_g_per_100g': double.infinity,
      });
      expect(f.amountGMl, 100, reason: 'Infinity miktar → DB varsayılanı');
      expect(f.caloriesPer100G, 0, reason: 'Infinity kalori → 0 (uydurma değer yok)');
      expect(f.proteinGPer100G, 0);
      expect(f.carbsGPer100G, 0);
      expect(f.fatGPer100G, 12, reason: 'geçerli alan korunur');
      expect(f.fiberGPer100G, isNull, reason: 'Infinity opsiyonel alan → null');
      // forAmount artık istisna fırlatmaz.
      expect(() => f.forAmount(200), returnsNormally);
    });

    test('amount 0/negatif 100\'e normalize edilir', () {
      // `forAmount(0)` negatif kalori üretebilirdi ve `DiaryRepository`
      // 0 miktarı zaten reddediyor — onay ekranı tutarsız değer göstermemeli.
      for (final bad in <double>[0, -50, double.nan, double.infinity]) {
        final f = RecognizedFood.fromJson({
          'name': 'X',
          'amount_g_ml': bad,
        });
        expect(f.amountGMl, 100, reason: 'amount=$bad');
        expect(f.toItem().servingSizeG, 100);
      }
    });
  });

  group('RecognizedFood.forAmount', () {
    test('kcal yuvarlanır, makrolar 1 ondalık (web parity)', () {
      final f = RecognizedFood(
        name: 'Yemek',
        amountGMl: 100,
        caloriesPer100G: 250,
        proteinGPer100G: 20,
        carbsGPer100G: 5.5,
        fatGPer100G: 18,
      );
      final v = f.forAmount(200);
      expect(v.kcal, 500); // 250*200/100 = 500
      expect(v.protein, 40.0);
      expect(v.carbs, 11.0);
      expect(v.fat, 36.0);
    });

    test('kesirli miktar doğru yuvarlanır', () {
      final f = RecognizedFood(
        name: 'A',
        amountGMl: 100,
        caloriesPer100G: 100,
        proteinGPer100G: 10,
        carbsGPer100G: 10,
        fatGPer100G: 10,
      );
      // 33g: kcal=33 (33/100*100), protein=3.3
      final v = f.forAmount(33);
      expect(v.kcal, 33);
      expect(v.protein, 3.3);
    });
  });

  group('RecognizedFood.toItem', () {
    test('FoodItem alan adları 100g normalize korunur, isCustom true', () {
      final f = RecognizedFood(
        name: 'Pizza',
        amountGMl: 150,
        caloriesPer100G: 280,
        proteinGPer100G: 12,
        carbsGPer100G: 35,
        fatGPer100G: 10,
      );
      final item = f.toItem();
      expect(item.id, 'recognized_Pizza');
      expect(item.name, 'Pizza');
      expect(item.servingSizeG, 150);
      expect(item.calories, 280);
      expect(item.proteinG, 12);
      expect(item.carbsG, 35);
      expect(item.fatG, 10);
      expect(item.isCustom, true);
      expect(item.foodId, isNull);
    });

    test('amount 0 ise servingSizeG 100 olur', () {
      final f = RecognizedFood(
        name: 'B',
        amountGMl: 0,
        caloriesPer100G: 50,
        proteinGPer100G: 1,
        carbsGPer100G: 2,
        fatGPer100G: 3,
      );
      expect(f.toItem().servingSizeG, 100);
    });

    test('toItem forAmount ile aynı sonucu verir', () {
      final f = RecognizedFood(
        name: 'Z',
        amountGMl: 100,
        caloriesPer100G: 200,
        proteinGPer100G: 15,
        carbsGPer100G: 25,
        fatGPer100G: 8,
      );
      final item = f.toItem();
      final fromFood = item.forAmount(100);
      final fromRecognized = f.forAmount(100);
      expect(fromFood.kcal, fromRecognized.kcal);
      expect(fromFood.protein, fromRecognized.protein);
      expect(fromFood.carbs, fromRecognized.carbs);
      expect(fromFood.fat, fromRecognized.fat);
    });
  });

  group('RecognitionResult.fromJson', () {
    test('foods dizisi parse edilir, description korunur', () {
      final r = RecognitionResult.fromJson({
        'foods': [
          {'name': 'A', 'calories_per_100g': 100, 'protein_g_per_100g': 5, 'carbs_g_per_100g': 10, 'fat_g_per_100g': 2},
          {'name': 'B', 'calories_per_100g': 200, 'protein_g_per_100g': 8, 'carbs_g_per_100g': 20, 'fat_g_per_100g': 5},
        ],
        'description': 'İki yemek tespit edildi',
      });
      expect(r.foods.length, 2);
      expect(r.foods.first.name, 'A');
      expect(r.foods.last.name, 'B');
      expect(r.description, 'İki yemek tespit edildi');
    });

    test('foods eksikse boş liste, description null', () {
      final r = RecognitionResult.fromJson({});
      expect(r.foods, isEmpty);
      expect(r.description, isNull);
    });

    test('foods null ise boş liste', () {
      final r = RecognitionResult.fromJson({'foods': null});
      expect(r.foods, isEmpty);
    });

    test('foods dizi değilse boş liste', () {
      final r = RecognitionResult.fromJson({'foods': 'string'});
      expect(r.foods, isEmpty);
    });

    test('foods içindeki bozuk eleman tüm sonucu DÜŞÜRMEZ', () {
      // `e as Map<String, dynamic>` zorlaması tek `null` eleman yüzünden
      // listeyi ve dolayısıyla **tanıma ekranının tamamını** çökertiyordu.
      // Edge function gövdesi LLM çıktısını olduğu gibi döndürebildiği
      // için bu varsayım değil olasılıktır.
      final r = RecognitionResult.fromJson({
        'foods': [
          null,
          'metin',
          42,
          {'name': 'Geçerli', 'calories_per_100g': 100},
          {'name': 'Geçerli2'},
        ],
      });
      expect(r.foods, hasLength(2));
      expect(r.foods.map((f) => f.name), ['Geçerli', 'Geçerli2']);
    });

    test('tamamen bozuk foods listesi boş döner (istisna değil)', () {
      final r = RecognitionResult.fromJson({
        'foods': [null, null],
      });
      expect(r.foods, isEmpty);
    });
  });
}
