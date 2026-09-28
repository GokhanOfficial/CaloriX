import 'dart:math' as math;

import 'package:calorix/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Semantik renklerin WCAG 2.1 kontrast eşiğini ölçen regresyon testi.
///
/// ## Arka plan
///
/// `AppColors.destructive/warning/success/info` web `index.css`'ten
/// **koyu tema** için seçilmişti. `ThemeMode.system` ve açık tema seçeneği
/// varken bu sabitler açık zeminde kullanılınca okunamaz oldu (ölçülen en
/// kötü: `warning` açık zeminde **1.93:1**). Bu test, `AppSemanticColors`
/// paletinin her iki temada da eşiği tutturduğunu kilitler.
///
/// ## Eşikler
///  * **3.0:1** — WCAG 1.4.11 Non-text Contrast (ikon, çubuk, veri grafiği
///    rengi; `AppSemanticColors` yalnızca bu tür kullanımlar için seçilir).
///  * **4.5:1** — AA normal metin. Metin olarak kullanılan alanlar
///    (`destructive`, `success`, `info` — BMI etiketi, ikon renkleri) bu
///    eşiği de geçer; `warning` **metin olarak kullanılmaz**
///    (`settings_page.dart` yalnızca ikon + %12 dolgu).
double relativeLuminance(Color c) {
  double channel(double v) => v <= 0.03928
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 (4.1) kontrast oranı — 1.0 … 21.0.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Metin olmayan UI eşiği.
const double kNonTextThreshold = 3.0;

/// Normal boy metin AA eşiği.
const double kTextAaThreshold = 4.5;

void main() {
  final light = AppTheme.light();
  final dark = AppTheme.dark();

  group('palet erişimi', () {
    test('iki temada da semantik palet `extensions` üzerinde', () {
      expect(light.semantic, same(AppColors.lightPalette));
      expect(dark.semantic, same(AppColors.darkPalette));
    });

    test('extension yoksa palete göre yedek döner (sessiz çökme yok)', () {
      final bare = ThemeData(brightness: Brightness.light);
      expect(bare.semantic.destructive, AppColors.destructiveLight);
      expect(
        ThemeData(brightness: Brightness.dark).semantic.warning,
        AppColors.warningDark,
      );
    });

    test('ThemeData önbelleklenir — her build yeni nesne üretmez', () {
      expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
      expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
    });
  });

  group('koyu tema kontrastı (web parity korunur)', () {
    // `ColorScheme.surface` üzerinde ölçülür; kart içi dolgular
    // (`surfaceContainerLow` vb.) arada küçük bir fark yaratır ama
    // `surface`'a göre daha yüksek kontrast verir.
    final s = dark.colorScheme.surface;
    final p = dark.semantic;

    test('tüm semantik renkler ≥ 3.0:1 (non-text)', () {
      final colors = {
        'success': p.success,
        'warning': p.warning,
        'destructive': p.destructive,
        'info': p.info,
        'macroProtein': p.macroProtein,
        'macroCarbs': p.macroCarbs,
        'macroFat': p.macroFat,
      };
      colors.forEach((name, c) {
        expect(
          contrastRatio(c, s),
          greaterThanOrEqualTo(kNonTextThreshold),
          reason: '$name koyu zeminde yetersiz kontrast: '
              '${contrastRatio(c, s).toStringAsFixed(2)}:1',
        );
      });
    });

    test('metin olarak kullanılan renkler ≥ 4.5:1 (AA)', () {
      for (final entry in {
        'destructive': p.destructive,
        'success': p.success,
        'info': p.info,
      }.entries) {
        expect(
          contrastRatio(entry.value, s),
          greaterThanOrEqualTo(kTextAaThreshold),
          reason: '${entry.key} koyu temada metin olarak okunmuyor: '
              '${contrastRatio(entry.value, s).toStringAsFixed(2)}:1',
        );
      }
    });

    test('web index.css dark paleti de non-text eşiğini geçer', () {
      // `AppColors.warning` gibi eski sabitler de koyu temada kullanılıyor
      // (A4 alanındaki feature kodları henüz `Theme.of(context).semantic`
      // okumuyor) — en azından ikon/dolgu olarak okunabilir olmalı.
      for (final entry in {
        'AppColors.success': AppColors.success,
        'AppColors.warning': AppColors.warning,
        'AppColors.destructive': AppColors.destructive,
        'AppColors.info': AppColors.info,
        'AppColors.macroProtein': AppColors.macroProtein,
        'AppColors.macroCarbs': AppColors.macroCarbs,
        'AppColors.macroFat': AppColors.macroFat,
      }.entries) {
        expect(
          contrastRatio(entry.value, s),
          greaterThanOrEqualTo(kNonTextThreshold),
          reason: '${entry.key} koyu temada okunmuyor: '
              '${contrastRatio(entry.value, s).toStringAsFixed(2)}:1',
        );
      }
    });
  });

  group('açık tema kontrastı (düzeltilen yer)', () {
    final s = light.colorScheme.surface;
    final p = light.semantic;

    test('tüm semantik renkler ≥ 3.0:1 (non-text)', () {
      final colors = {
        'success': p.success,
        'warning': p.warning,
        'destructive': p.destructive,
        'info': p.info,
        'macroProtein': p.macroProtein,
        'macroCarbs': p.macroCarbs,
        'macroFat': p.macroFat,
      };
      colors.forEach((name, c) {
        expect(
          contrastRatio(c, s),
          greaterThanOrEqualTo(kNonTextThreshold),
          reason: '$name açık zeminde yetersiz: '
              '${contrastRatio(c, s).toStringAsFixed(2)}:1',
        );
      });
    });

    test('metin olarak kullanılan renkler ≥ 4.5:1 (AA)', () {
      for (final entry in {
        'destructive': p.destructive,
        'success': p.success,
        'info': p.info,
      }.entries) {
        expect(
          contrastRatio(entry.value, s),
          greaterThanOrEqualTo(kTextAaThreshold),
          reason: '${entry.key} açık temada metin olarak okunmuyor: '
              '${contrastRatio(entry.value, s).toStringAsFixed(2)}:1',
        );
      }
    });

    test('destructive eski sabiti 4.5:1 ALTINDA (regresyon kanıtı)', () {
      // Bu test, "eski" paletin gerçekten yetersiz olduğunu sabitler; yeni
      // palet yukarıdaki testlerde geçtiği için düzeltmenin işe yaradığı
      // kanıtlanır.
      final old = contrastRatio(AppColors.destructive, s);
      expect(old, lessThan(kTextAaThreshold));
      expect(
        contrastRatio(AppColors.destructiveLight, s),
        greaterThan(old),
      );
    });

    test('warning eski sabiti ~1.9:1 (bilinen bulgu)', () {
      // Tur 1 raporundaki ölçüm: 1.93:1. Yeni ton ≥ 4.0.
      final old = contrastRatio(AppColors.warning, s);
      expect(old, lessThan(2.1));
      expect(contrastRatio(AppColors.warningLight, s), greaterThan(4.0));
    });

    test('lightPalette/darkPalette birbirinin aynısı değil', () {
      expect(AppColors.lightPalette.destructive,
          isNot(AppColors.darkPalette.destructive));
      expect(AppColors.lightPalette.warning, isNot(AppColors.warningDark));
    });
  });

  group('ThemeExtension sözleşmesi', () {
    test('copyWith tüm alanları korur/değiştirir', () {
      final base = AppColors.lightPalette;
      final copy = base.copyWith(warning: Colors.pink);
      expect(copy.warning, Colors.pink);
      expect(copy.destructive, base.destructive);
      expect(copy.macroFat, base.macroFat);
    });

    test('lerp uç noktalarda tam değere ulaşır', () {
      final a = AppColors.lightPalette;
      final b = AppColors.darkPalette;
      expect(a.lerp(b, 0).destructive, a.destructive);
      expect(a.lerp(b, 1).destructive, b.destructive);
      // Yanlış tip → this döner (Material'in beklediği savunma).
      expect(a.lerp(null, 0.5), same(a));
    });
  });
}
