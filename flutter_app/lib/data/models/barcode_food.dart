import 'recognized_food.dart';

/// Barkod akışının yemek verisi — web `BarcodeScanDialog` `FoodData` karşılığı.
///
/// Hem DB'den bulunan (`fromDb: true`) hem de AI ile tanınan (`fromDb: false`)
/// tek bir ürünü temsil eder. Değerler 100g/ml başınadır (web ile aynı).
/// Kayıt sırasında `amount_g_ml` ile bu değerlerden `calculated_*` hesaplanır.
class BarcodeFood {
  BarcodeFood({
    required this.name,
    required this.amountGMl,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.brand,
    this.barcode,
    this.servingSizeG,
    this.saturatedFatG,
    this.transFatG,
    this.sugarsG,
    this.fiberG,
    this.saltG,
    this.novaScore,
    this.nutriScore,
    this.confidence,
    this.fromDb = false,
    this.foodId,
  });

  /// Düzenlenebilir — web `foodData` nesnesi gibi result adımında değişebilir.
  String name;
  String? brand;

  /// Taramadan/manuelden gelir; result adımında değiştirilmez.
  final String? barcode;

  /// Kullanıcının yiyeceği miktarı (g/ml) — kayıt için.
  double amountGMl;

  /// Ürünün standart porsiyonu (g) — yeni `foods` satırına yazılır.
  double? servingSizeG;

  // --- 100g başına ana makrolar (düzenlenebilir) ---
  double calories;
  double proteinG;
  double carbsG;
  double fatG;

  // --- Genişletilmiş besin (100g başına, opsiyonel, düzenlenebilir) ---
  double? saturatedFatG;
  double? transFatG;
  double? sugarsG;
  double? fiberG;
  double? saltG;
  int? novaScore;
  String? nutriScore;

  /// AI güven skoru (yalnızca `fromDb: false` iken anlamlı) — değiştirilmez.
  final double? confidence;

  /// DB'den bulunmuş mu? `true` ise `foodId` doludur ve yeni satır oluşturulmaz.
  final bool fromDb;

  /// DB yemeği id'si (`fromDb: true` iken dolu).
  final String? foodId;

  /// `amount` gram için hesaplanan değerler (web `handleSave` parity):
  /// kcal = round(cal/100 * amount), makrolar 1 ondalık.
  ({int kcal, double protein, double carbs, double fat}) forAmount(
    double amount,
  ) {
    return (
      kcal: (calories * amount / 100).round(),
      protein: _round1(proteinG * amount / 100),
      carbs: _round1(carbsG * amount / 100),
      fat: _round1(fatG * amount / 100),
    );
  }

  static double _round1(double v) => (v * 10).round() / 10;

  /// AI tanıma yanıtındaki ilk yemekten (`RecognizedFood`-benzeri Map)
  /// `BarcodeFood` üretir — web `analyzeWithAI` içindeki `firstFood` eşlemesi.
  /// Yeni alan adları öncelikli, eski kısaltmalar tolere edilir.
  factory BarcodeFood.fromAiFood(Map<String, dynamic> f, String? barcodeValue) {
    double numOr(Object? v) => (v is num ? v : 0).toDouble();
    double? numOrNull(Object? v) => v is num ? v.toDouble() : null;
    int? intOrNull(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    final amount = numOr(f['amount_g_ml']);
    return BarcodeFood(
      name: f['name'] as String? ?? '',
      barcode: barcodeValue,
      amountGMl: amount > 0 ? amount : 100, // web: `amount_g_ml || 100`
      calories: numOr(f['calories_per_100g']) != 0
          ? numOr(f['calories_per_100g'])
          : numOr(f['calories']),
      proteinG: numOr(f['protein_g_per_100g']) != 0
          ? numOr(f['protein_g_per_100g'])
          : numOr(f['protein_g']),
      carbsG: numOr(f['carbs_g_per_100g']) != 0
          ? numOr(f['carbs_g_per_100g'])
          : numOr(f['carbs_g']),
      fatG: numOr(f['fat_g_per_100g']) != 0
          ? numOr(f['fat_g_per_100g'])
          : numOr(f['fat_g']),
      saturatedFatG: numOrNull(f['saturated_fat_g_per_100g']),
      transFatG: numOrNull(f['trans_fat_g_per_100g']),
      sugarsG: numOrNull(f['sugars_g_per_100g']),
      fiberG: numOrNull(f['fiber_g_per_100g']),
      saltG: numOrNull(f['salt_g_per_100g']),
      novaScore: intOrNull(f['nova_score']),
      nutriScore: (f['nutri_score'] as String?)?.toUpperCase(),
      confidence: numOrNull(f['confidence']),
      fromDb: false,
    );
  }

  /// AI tanıma yanıtındaki [RecognizedFood]'dan `BarcodeFood` üretir —
  /// barkod akışının notFound adımında `recognize-food`/`recognize-food-text`
  /// döndüğü ilk yemek için. Değerler 100g başına (modelle aynı).
  factory BarcodeFood.fromRecognizedFood(
    RecognizedFood f,
    String? barcodeValue,
  ) {
    return BarcodeFood(
      name: f.name,
      barcode: barcodeValue,
      amountGMl: f.amountGMl > 0 ? f.amountGMl : 100,
      calories: f.caloriesPer100G,
      proteinG: f.proteinGPer100G,
      carbsG: f.carbsGPer100G,
      fatG: f.fatGPer100G,
      saturatedFatG: f.saturatedFatGPer100G,
      transFatG: f.transFatGPer100G,
      sugarsG: f.sugarsGPer100G,
      fiberG: f.fiberGPer100G,
      saltG: f.saltGPer100G,
      novaScore: f.novaScore,
      nutriScore: f.nutriScore?.toUpperCase(),
      confidence: f.confidence,
      fromDb: false,
    );
  }

  /// DB `foods` + `food_nutrition` join satırından `BarcodeFood` üretir.
  /// PostgREST 1:1 join'i Map veya tek elemanlı List dönebilir.
  factory BarcodeFood.fromDbRow(Map<String, dynamic> row) {
    final nutrition = _firstNutrition(row['food_nutrition']);
    double numOr(Object? v) => (v is num ? v : 0).toDouble();

    return BarcodeFood(
      name: row['name'] as String? ?? '',
      brand: row['brand'] as String?,
      barcode: row['barcode'] as String?,
      servingSizeG: (row['serving_size_g'] as num?)?.toDouble(),
      amountGMl: (row['serving_size_g'] as num?)?.toDouble() ?? 100,
      calories: nutrition != null ? numOr(nutrition['kcal']) : 0,
      proteinG: nutrition != null ? numOr(nutrition['protein_g']) : 0,
      carbsG: nutrition != null ? numOr(nutrition['carbs_g']) : 0,
      fatG: nutrition != null ? numOr(nutrition['fat_g']) : 0,
      fiberG: (nutrition?['fiber_g'] as num?)?.toDouble(),
      sugarsG: (nutrition?['sugar_g'] as num?)?.toDouble(), // DB: sugar_g
      saltG: (nutrition?['salt_g'] as num?)?.toDouble(),
      saturatedFatG: (nutrition?['saturated_fat_g'] as num?)?.toDouble(),
      transFatG: (nutrition?['trans_fat_g'] as num?)?.toDouble(),
      novaScore: _toInt(nutrition?['nova_score']),
      nutriScore: (nutrition?['nutri_score'] as String?)?.toUpperCase(),
      fromDb: true,
      foodId: row['id'] as String?,
    );
  }

  static Map<String, dynamic>? _firstNutrition(Object? join) {
    if (join is Map<String, dynamic>) return join;
    if (join is List && join.isNotEmpty) {
      return join.first as Map<String, dynamic>;
    }
    return null;
  }

  static int? _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }

  /// Kayıt için `custom_name` — web parity: `name + (brand ? " ($brand)" : "")`.
  String get displayName => brand != null && brand!.isNotEmpty
      ? '$name ($brand)'
      : name;
}
