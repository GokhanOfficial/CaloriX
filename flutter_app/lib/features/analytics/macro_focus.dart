import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Dashboard makro kartlarından analitiğe derin bağlantı için odak makro.
///
/// `/analytics?macro=protein|carbs|fat` sorgu parametresinden
/// [MacroFocus.fromName] ile çözülür; `AnalyticsPage.focusedMacro` olarak
/// iletilir ve seçili makro için per-macro grafik kartını gösterir.
enum MacroFocus {
  protein,
  carbs,
  fat;

  /// Sorgu parametresinden güvenli çözüm — `null`/geçersiz → `null` veya
  /// ilk değer. Rotada `state.uri.queryParameters['macro']` ile kullanılır.
  static MacroFocus? fromName(String? name) {
    if (name == null) return null;
    return values.firstWhere(
      (m) => m.name == name,
      orElse: () => values.first,
    );
  }

  /// Etiket i18n anahtarı (`settings.goals.protein` vb.).
  String get labelKey => switch (this) {
        MacroFocus.protein => 'settings.goals.protein',
        MacroFocus.carbs => 'settings.goals.carbs',
        MacroFocus.fat => 'settings.goals.fat',
      };

  /// Grafik/kart rengi — `AppColors.macro*` (web `--macro-*` parity).
  Color get color => switch (this) {
        MacroFocus.protein => AppColors.macroProtein,
        MacroFocus.carbs => AppColors.macroCarbs,
        MacroFocus.fat => AppColors.macroFat,
      };

  /// Odak makro için hedef yüzdesi — per-macro grafik spot değeri.
  ///
  /// `(value/target*100)`'ü 0–200 aralığına clample. Hedef 0/≤0 ise 0
  /// (sıfıra bölme koruması). 100 = hedefe ulaşıldı; >100 = aşıldı (grafik
  /// üst sınır 200). Grafik kartı bu değeri `FlSpot.y` olarak kullanır.
  static double percentOfTarget({required double value, required double target}) {
    if (target <= 0) return 0;
    return (value / target * 100).clamp(0.0, 200.0);
  }
}
