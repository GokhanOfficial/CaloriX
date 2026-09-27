import 'food_item.dart';

/// `recognize-food` / `recognize-food-text` edge fonksiyonlarının `foods[]`
/// dizisindeki tek öğe — web `FoodItem` tanıma kontratı.
///
/// Besin değerleri **100g/ml başına** normalize edilmiştir. `amount_g_ml`
/// ise AI'nin tespit ettiği tahmini porsiyon miktarıdır (onay ekranında
/// varsayılan miktar olarak kullanılır).
///
/// Sunucu hem yeni alan adlarını (`calories_per_100g` …) hem de eski
/// kısaltmaları (`calories`, `protein_g` …) döndürebilir; [fromJson]
/// ikisini de tolere eder (web istemcisiyle aynı davranış).
class RecognizedFood {
  const RecognizedFood({
    required this.name,
    required this.amountGMl,
    required this.caloriesPer100G,
    required this.proteinGPer100G,
    required this.carbsGPer100G,
    required this.fatGPer100G,
    this.saturatedFatGPer100G,
    this.transFatGPer100G,
    this.sugarsGPer100G,
    this.fiberGPer100G,
    this.saltGPer100G,
    this.novaScore,
    this.nutriScore,
    this.confidence,
  });

  final String name;

  /// AI tespit ettiği tahmini porsiyon (g/ml) — varsayılan miktar.
  final double amountGMl;

  /// 100g/ml başına kcal.
  final double caloriesPer100G;
  final double proteinGPer100G;
  final double carbsGPer100G;
  final double fatGPer100G;
  final double? saturatedFatGPer100G;
  final double? transFatGPer100G;
  final double? sugarsGPer100G;
  final double? fiberGPer100G;
  final double? saltGPer100G;
  final int? novaScore;
  final String? nutriScore;
  final double? confidence;

  /// `amount` g/ml için hesaplanmış besin değerleri (web parity):
  /// kcal yuvarlanır, makrolar 1 ondalık basamağa yuvarlanır.
  ({int kcal, double protein, double carbs, double fat}) forAmount(
    double amount,
  ) {
    return (
      kcal: (caloriesPer100G * amount / 100).round(),
      protein: _round1(proteinGPer100G * amount / 100),
      carbs: _round1(carbsGPer100G * amount / 100),
      fat: _round1(fatGPer100G * amount / 100),
    );
  }

  static double _round1(double v) => (v * 10).round() / 10;

  /// Tanıma onay akışında mevcut [FoodItem] confirm dialog'unu yeniden
  /// kullanabilmek için birleşik tipe dönüştürür. Tanıma sonucu her zaman
  /// "custom" kabul edilir (food_id yok); kayıt `custom_name` ile yapılır.
  ///
  /// `FoodItem` alanları `calories/proteinG/carbsG/fatG` 100g başınadır —
  /// buradaki `*Per100G` değerleriyle birebir eşleşir.
  FoodItem toItem() => FoodItem(
        id: 'recognized_$name',
        name: name,
        servingSizeG: amountGMl > 0 ? amountGMl : 100,
        calories: caloriesPer100G,
        proteinG: proteinGPer100G,
        carbsG: carbsGPer100G,
        fatG: fatGPer100G,
        isCustom: true,
      );

  factory RecognizedFood.fromJson(Map<String, dynamic> json) {
    double numOr(String key, double fallback) {
      final v = json[key];
      if (v is num) return v.toDouble();
      return fallback;
    }

    double? numOpt(String key) {
      final v = json[key];
      if (v is num) return v.toDouble();
      return null;
    }

    // Yeni alan adları öncelikli; yoksa eski kısaltmalar.
    final calories = numOr('calories_per_100g', numOr('calories', 0));
    final protein = numOr('protein_g_per_100g', numOr('protein_g', 0));
    final carbs = numOr('carbs_g_per_100g', numOr('carbs_g', 0));
    final fat = numOr('fat_g_per_100g', numOr('fat_g', 0));

    final nova = json['nova_score'];
    return RecognizedFood(
      name: (json['name'] as String?) ?? '',
      amountGMl: numOr('amount_g_ml', 100),
      caloriesPer100G: calories,
      proteinGPer100G: protein,
      carbsGPer100G: carbs,
      fatGPer100G: fat,
      saturatedFatGPer100G: numOpt('saturated_fat_g_per_100g'),
      transFatGPer100G: numOpt('trans_fat_g_per_100g'),
      sugarsGPer100G: numOpt('sugars_g_per_100g'),
      fiberGPer100G: numOpt('fiber_g_per_100g'),
      saltGPer100G: numOpt('salt_g_per_100g'),
      novaScore: nova is int ? nova : (nova is num ? nova.toInt() : null),
      nutriScore: json['nutri_score'] as String?,
      confidence: numOpt('confidence'),
    );
  }
}

/// `recognize-food` / `recognize-food-text` yanıtı — `{ foods, description }`.
class RecognitionResult {
  const RecognitionResult({required this.foods, this.description});

  final List<RecognizedFood> foods;
  final String? description;

  factory RecognitionResult.fromJson(Map<String, dynamic> json) {
    final raw = json['foods'];
    final list = raw is List ? raw : const <dynamic>[];
    return RecognitionResult(
      foods: list
          .map((e) => RecognizedFood.fromJson(e as Map<String, dynamic>))
          .toList(),
      description: json['description'] as String?,
    );
  }
}
