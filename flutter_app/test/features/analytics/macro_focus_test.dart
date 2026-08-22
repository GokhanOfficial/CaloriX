import 'package:calorix/core/theme/app_theme.dart';
import 'package:calorix/features/analytics/macro_focus.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faz 3 — per-macro analitik derin bağlantı çekirdek mantığı.
///
/// `MacroFocus.fromName` rotadaki `state.uri.queryParameters['macro']`'yu
/// güvenli çözer; `percentOfTarget` per-macro grafik spot değerini üretir
/// (`analytics_page.dart` `_FocusedMacroChartCard`).
void main() {
  group('MacroFocus.fromName', () {
    test('geçerli isim → ilgili değer', () {
      expect(MacroFocus.fromName('protein'), MacroFocus.protein);
      expect(MacroFocus.fromName('carbs'), MacroFocus.carbs);
      expect(MacroFocus.fromName('fat'), MacroFocus.fat);
    });

    test('null → null (varsayılan analitik sayfası)', () {
      expect(MacroFocus.fromName(null), isNull);
    });

    test('geçersiz isim → ilk değer (protein), null değil', () {
      // Rota güvenliği: bilinmeyen query param null patlamasın.
      expect(MacroFocus.fromName(''), MacroFocus.protein);
      expect(MacroFocus.fromName('calories'), MacroFocus.protein);
      expect(MacroFocus.fromName('PROTEIN'), MacroFocus.protein);
    });
  });

  group('MacroFocus.labelKey', () {
    test('settings.goals.* i18n anahtarları', () {
      expect(MacroFocus.protein.labelKey, 'settings.goals.protein');
      expect(MacroFocus.carbs.labelKey, 'settings.goals.carbs');
      expect(MacroFocus.fat.labelKey, 'settings.goals.fat');
    });
  });

  group('MacroFocus.color', () {
    test('AppColors.macro* parity (web --macro-* renkleri)', () {
      expect(MacroFocus.protein.color, AppColors.macroProtein);
      expect(MacroFocus.carbs.color, AppColors.macroCarbs);
      expect(MacroFocus.fat.color, AppColors.macroFat);
    });
  });

  group('MacroFocus.percentOfTarget', () {
    test('hedefin altında → orantılı yüzde', () {
      expect(
        MacroFocus.percentOfTarget(value: 75, target: 150),
        closeTo(50.0, 1e-9),
      );
      expect(
        MacroFocus.percentOfTarget(value: 30, target: 200),
        closeTo(15.0, 1e-9),
      );
    });

    test('tam hedef → 100', () {
      expect(
        MacroFocus.percentOfTarget(value: 150, target: 150),
        closeTo(100.0, 1e-9),
      );
    });

    test('hedef aşıldı → >100 ama 200 üst sınırına clamp', () {
      // 300/150 = 200 → üst sınır.
      expect(
        MacroFocus.percentOfTarget(value: 300, target: 150),
        closeTo(200.0, 1e-9),
      );
      // 400/150 = 266.67 → 200.
      expect(
        MacroFocus.percentOfTarget(value: 400, target: 150),
        closeTo(200.0, 1e-9),
      );
    });

    test('hedef 0/≤0 → 0 (sıfıra bölme koruması)', () {
      expect(MacroFocus.percentOfTarget(value: 100, target: 0), 0);
      expect(MacroFocus.percentOfTarget(value: 100, target: -10), 0);
    });

    test('negatif değer → 0 alt sınırına clamp', () {
      expect(
        MacroFocus.percentOfTarget(value: -50, target: 150),
        closeTo(0.0, 1e-9),
      );
    });
  });
}
