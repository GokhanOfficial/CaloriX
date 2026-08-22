/// Arama / favori / son-yenilenler listelerinde kullanılan birleşik öğe.
///
/// Web `FoodSearchResult` + `FavoriteFood` + `RecentFood` tiplerinin
/// Dart karşılığı — besin değerleri **100g başına** normalize edilmiştir.
class FoodItem {
  const FoodItem({
    required this.id,
    required this.name,
    this.foodId,
    this.brand,
    this.servingSizeG,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.isCustom = false,
    this.useCount,
    this.lastUsedAt,
  });

  /// DB yemeğinde `foods.id`, custom'da `custom_<entry.id>` (web parity).
  final String id;

  /// `foods.id` — custom girdilerde null.
  final String? foodId;

  final String name;
  final String? brand;

  /// Önerilen porsiyon (g/ml). Custom girdide girişin miktarı (web parity).
  final double? servingSizeG;

  /// 100g başına kcal.
  final double calories;

  /// 100g başına protein (g).
  final double proteinG;

  /// 100g başına karbonhidrat (g).
  final double carbsG;

  /// 100g başına yağ (g).
  final double fatG;

  /// Kullanıcının manuel/özel girdisi mi?
  final bool isCustom;

  /// Sadece favorilerde: kaç kez kullanıldığı.
  final int? useCount;

  /// Sadece son yenilenlerde: son kullanım zamanı.
  final String? lastUsedAt;

  /// `amount` g/ml için hesaplanmış besin değerleri (web parity):
  /// kcal yuvarlanır, makrolar 1 ondalık basamağa yuvarlanır.
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
}
