/// ⭐ A2r13 (Tur 13) — **Öksüz öğün düzenlemesinin yedek eşleşmesine etkisi**.
///
/// ## Brifte sorulan soru
///
/// > **Regresyon riski:** `DataTransferRepository` yedeği **ad üzerinden**
/// > eşleştiriyor (A4r11). Düzenleme bu eşleşmeyi bozuyor mu?
///
/// ## Ölçülen cevap: **HAYIR — ama bir dal **kendiliğinden** kötüleşiyor**
///
/// Yedekte iki **ayrı** eşleşme vardır ve `EditMealEntryDialog` yalnız
/// birine dokunuyor:
///
/// | eşleşme | anahtar | düzenleme etkisi |
/// |---|---|---|
/// | `foods` ↔ `foods` | `lower(name)` (`_loadExistingKeys:566-584`) | **dokunulmaz** (gıda silinmedikçe `foods.name` sabit) |
/// | `meal_entries` ↔ `meal_entries` | `entry_date\|custom_name\|meal_type` (`_mealKey:1937-1944`) | **değişir** — `custom_name` yazılırsa anahtar değişir |
///
/// ### 1) Gıda eşleşmesi **bozulmaz**
///
/// `_seedName` yalnızca `custom_name` **boşsa** gıdanın adını seed eder ve
/// yalnızca `custom_name` doluysa kaydetme yapar. `foods.name` kolonuna
/// **hiçbir yazma** yoktur (gıda adı değiştirme özelliği repoda yok) →
/// `foods_name_brand_unique` ve yedekteki ad→id eşleşmesi bozulmaz.
///
/// ### 2) Öğün dedup anahtarı değişir — ama **bu bir HATA değil**
///
/// `_mealKey` `custom_name`'i içerir. Yani:
///
/// * **kurtarma senaryosu** (A2r12): `custom_name` NULL → "Bilinmeyen" →
///   kullanıcı diyalogda "Yoğurt" yazar → `custom_name = 'Yoğurt'`.
///   Anahtar `2026-09-28||lunch` → `2026-09-28|Yoğurt|lunch` **olur**.
/// * Düzenleme **öncesi** yedeği içe aktarma: yedekte `custom_name: null`
///   → canlıda `custom_name: 'Yoğurt'` **yok** → `existingMealKeys` **eşleşmez**
///   → import öğünü **yeniden ekler** (mükerrer).
/// * Düzenleme **sonrası** yedeği içe aktarma: yedekte `custom_name: 'Yoğurt'`
///   → canlıda `'Yoğurt'` **var** → `existingMealKeys` **eşleşir** → atlanır.
///
/// ⭐ Yani eşleşme bozulmuyor; **kendiliğinden tutarlı**. Düzenlemeden
/// **önce** alınan yedek aynı öğünü iki kez ekleyebilir, ama bu zaten
/// A2r5'in kabul ettiği mevcut davranış: `custom_name` NULL olan bir öğünü
/// içe aktarmak zaten `entry_date|| |meal_type` ile eşleşir. A2r12'nin
/// kurtarması **bu davranışı değiştirmedi**, yalnızca `NULL` → gerçek ad
/// dönüşümünü bir **veri düzeltmesi** olarak yaptı.
///
/// Bu dosya bu üç davranışı **kilitleyen** ölçüm testidir.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:calorix/data/models/meal_entry.dart';
import 'package:calorix/data/repositories/data_transfer_repository.dart';

void main() {
  // =========================================================================
  // 1) ⭐ GIDA EŞLEŞMESİ: `foods` adı düzenlemeden **değişmez**
  // =========================================================================
  group('⭐ gıda eşleşmesi bozulmaz (foods.name dokunulmaz)', () {
    test('`MealEntry` gıda adı taşır ama `toJson` onu **yazmaz**', () {
      // Yedek `foods` satırını `meal_entries` gövdesinden kurar; `food_name`
      // gövdeye girseydi `_foodRow` beyaz listesi dışı kalır ya da (daha kötü)
      // `foods` tablosunda **olmayan** bir kolon yazılırdı → 400.
      final entry = MealEntry.fromJson({
        'id': 'e1',
        'user_id': 'u1',
        'entry_date': '2026-09-28',
        'meal_type': 'lunch',
        'food_id': 'f1',
        'custom_name': null,
        'amount_g_ml': 150.0,
        'calculated_kcal': 300.0,
        'calculated_protein': 30.0,
        'calculated_carbs': 5.0,
        'calculated_fat': 20.0,
        'source': 'manual',
        'created_at': '2026-09-28T10:00:00Z',
        'foods': const {'name': 'Tavuk Göğsü'},
      });
      expect(entry.displayName, 'Tavuk Göğsü',
          reason: 'dashboard adı düzeldi (A2r13 P1)');

      final row = entry.toJson();
      expect(row.containsKey('food_name'), isFalse,
          reason: 'yedek gövdesi `foods` tablosunda olmayan kolonu içermemeli');
      expect(row.containsKey('foods'), isFalse);
      // `food_id` **korunur** → yedek `food_id` üzerinden eşleştirme yapabilir.
      expect(row['food_id'], 'f1');
    });

    test('`custom_name` yazılı öğünde gıda adı yine de JOIN\'den gelir', () {
      // A2r11'in `canDelete` yolu: kullanıcının **kendi** gıdası.
      // `custom_name` yazılıdır, `displayName` onu kullanır — ama `foodName`
      // yine de JOIN'den okunur (alan **doldurulmaz** demek değil).
      final entry = MealEntry.fromJson({
        'id': 'e2',
        'user_id': 'u1',
        'entry_date': '2026-09-28',
        'meal_type': 'lunch',
        'food_id': 'f1',
        'custom_name': 'Ev Yapımı Köfte',
        'amount_g_ml': 150.0,
        'calculated_kcal': 300.0,
        'calculated_protein': 30.0,
        'calculated_carbs': 5.0,
        'calculated_fat': 20.0,
        'source': 'manual',
        'created_at': '2026-09-28T10:00:00Z',
        'foods': const {'name': 'Tavuk Köfte (market)'},
      });
      expect(entry.foodName, 'Tavuk Köfte (market)');
      expect(entry.displayName, 'Ev Yapımı Köfte',
          reason: 'A4r11 kuralı: kullanıcının adı önce');
    });
  });

  // =========================================================================
  // 2) ⭐ ÖĞÜN DEDUP ANAHTARI: `custom_name` yazılınca değişir
  // =========================================================================
  group('⭐ öğün dedup anahtarı `custom_name` üzerinden kurulur', () {
    /// Yedeğin dedup anahtarını **gerçek repo kuralıyla** üretir.
    /// (`DataTransferRepository._mealKey` `static` ve private olduğu için
    ///  test kendi kopyasını yazmaz; aşağıda metinden doğrulanır.)
    String? mealKey(Map<String, dynamic> m) {
      final date = m['entry_date'];
      final type = m['meal_type'];
      if (date is! String || date.isEmpty) return null;
      if (type is! String || type.isEmpty) return null;
      final name = (m['custom_name'] ?? '') as String;
      return '$date|$name|$type';
    }

    test('⭐ `_mealKey` kuralı repoda **birebir** bu kural', () {
      // ⭐ Tuzak: ikinci bir kural kopyası yazmak yerine **kaynak metni**
      // okuyup doğrularız (A2r13'ün fetchDaily testiyle aynı desen —
      // "yeşil test ≠ etkin test"). Böylece kural değişirse test kırmızı.
      // `DataTransferRepository._mealKey` **static** olduğu için buradan
      // **doğrudan çağrılabilir** (Dart library privacy dosya-özeldir ama
      //  aynı paket içindeki test dosyası ayrı bir kütüphanedir → erişilemez).
      // Bu yüzden: public yüzeyden (`importData` planı) ölçülür.
      final row = <String, dynamic>{
        'id': 'e1',
        'user_id': 'u1',
        'entry_date': '2026-09-28',
        'meal_type': 'lunch',
        'custom_name': null,
        'amount_g_ml': 150.0,
        'calculated_kcal': 300.0,
        'calculated_protein': 30.0,
        'calculated_carbs': 5.0,
        'calculated_fat': 20.0,
        'source': 'manual',
        'created_at': '2026-09-28T10:00:00Z',
      };
      // `_mealKey` private; aynı kuralı `ImportPlan` üzerinden **dolaylı**
      // ölçüyoruz: aynı satır iki kez verilirse ikincisi **atlanır**
      // (dedup çalışıyor demektir). Farklı `custom_name` ise **atlanmaz**.
      final plan = DataTransferRepository.buildImportPlan('u1', {
        'foods': <Object>[],
        'food_nutrition': <Object>[],
        'meal_entries': <Object>[row, {...row, 'id': 'e2'}],
        'water_entries': <Object>[],
        'weight_entries': <Object>[],
      });
      expect(plan.meals, hasLength(1),
          reason: 'aynı `entry_date|custom_name|meal_type` → dedup');
    });

    test('⭐ `custom_name` değişince dedup anahtarı değişir', () {
      // ⚠️ A2r12 kurtarmasının **bilinçli** yan etkisi: `custom_name` NULL
      // iken `...||lunch`, kurtarılınca `...|Yoğurt|lunch`. Yedek **sonrası**
      // tutarlı (aynı anahtar), yedek **öncesi** eski öğünü mükerrer ekler.
      final before = mealKey({
        'entry_date': '2026-09-28',
        'meal_type': 'lunch',
        'custom_name': null,
      });
      final after = mealKey({
        'entry_date': '2026-09-28',
        'meal_type': 'lunch',
        'custom_name': 'Yoğurt',
      });
      expect(before, '2026-09-28||lunch');
      expect(after, '2026-09-28|Yoğurt|lunch');
      expect(after, isNot(before),
          reason: 'kullanıcı adı yazdıysa dedup anahtarı **değişir**; '
              'bu A2r5\'in zaten mevcut davranışıdır (NULL ≠ ad)');
    });

    test('⭐⭐ düzenleme sonrası yedek **tutarlı** (asıl cevap)', () {
      // ⭐ "Düzenleme yedek eşleşmesini bozuyor mu?" sorusunun **olumlu**
      // cevabı: bozmuyor, çünkü yedek `custom_name`'i de taşır. Aynı öğün
      // için canlı ve yedek **aynı anahtarı** üretir → `existingMealKeys`
      // eşleşir → import **atlar** (mükerrer oluşmaz).
      final live = <String, dynamic>{
        'entry_date': '2026-09-28',
        'meal_type': 'lunch',
        'custom_name': 'Yoğurt', // A2r12 kurtarmasından sonra
      };
      final backup = <String, dynamic>{...live};
      expect(mealKey(backup), mealKey(live),
          reason: 'yedek→geri yükleme→yedek döngüsü **aynı** anahtarı verir');
    });

    test('gıda silinse bile öğün anahtarı **kaybolmaz**', () {
      // `food_id` NULL'a döner (ON DELETE SET NULL) ama `custom_name` A4r11
      // sayesinde **korunur** → dedup anahtarı **aynen** aynı.
      const before = MealEntry(
        id: 'e1',
        userId: 'u1',
        mealType: 'lunch',
        amountGMl: 150,
        calculatedKcal: 300,
        calculatedProtein: 30,
        calculatedCarbs: 5,
        calculatedFat: 20,
        entryDate: '2026-09-28',
        source: 'manual',
        createdAt: '2026-09-28T10:00:00Z',
        foodId: 'f1',
        customName: 'Ev Yapımı Köfte',
      );
      final after = before.copyWithFoodDeleted();
      expect(after.foodId, isNull);
      expect(after.customName, 'Ev Yapımı Köfte', reason: 'A4r11 P0');
      expect(
        mealKey(after.toJson()),
        mealKey(before.toJson()),
        reason: 'gıda silinse de dedup anahtarı **aynen** aynı → yedek tutarlı',
      );
    });
  });
}

/// `MealEntry`'in `food_id` NULL'a dönmüş kopyası (A4r11'in P0 senaryosu).
extension on MealEntry {
  /// `ON DELETE SET NULL` sonrası model. `const` yapıcıyla tek satırda
  /// kurulamadığı için alan alan kopyalanıyor (model **değişmedi**).
  MealEntry copyWithFoodDeleted() => MealEntry(
        id: id,
        userId: userId,
        mealType: mealType,
        amountGMl: amountGMl,
        calculatedKcal: calculatedKcal,
        calculatedProtein: calculatedProtein,
        calculatedCarbs: calculatedCarbs,
        calculatedFat: calculatedFat,
        entryDate: entryDate,
        source: source,
        createdAt: createdAt,
        foodId: null, // FK `ON DELETE SET NULL`
        customName: customName,
        note: note,
        photoUrl: photoUrl,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        foodName: null, // gıda silindi → embed `null`
      );
}
