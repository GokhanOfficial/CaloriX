import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web uygulamasıyla uyumlu tema paleti (tailwind dark-default).
///
/// ## Kontrast sözleşmesi (WCAG 2.1)
///
/// Web `index.css` değerleri **koyu tema** için seçilmişti ve Flutter'da
/// `ThemeMode.system`/açık tema ile de kullanılıyordu. Ölçülen oranlar
/// (bkz. `test/core/theme/app_theme_contrast_test.dart`):
///
/// | Renk              | açık zemin (`#F4FBF8`) | koyu zemin (`#0E1513`) |
/// |-------------------|-----------------------:|----------------------:|
/// | `destructive` eski|                  4.30 |                  4.10 |
/// | `destructive` yeni|                  5.20 |                  6.67 |
/// | `warning` eski    |                  1.93 |                  9.13 |
/// | `warning` yeni    |                  4.04 |                 11.77 |
/// | `success` eski    |                  2.18 |                  8.08 |
/// | `success` yeni    |                  4.73 |                 11.19 |
/// | `info` eski       |                  2.74 |                  6.43 |
/// | `info` yeni       |                  5.02 |                  9.90 |
///
/// Kural: **her iki zeminde de ≥ 3.0:1** (WCAG 1.4.11 "non-text
/// contrast"; ikon, ilerleme çubuğu, veri çubuğu). Düz metin olarak
/// kullanılan yerlerde (BMI etiketi `personal_info_dialog.dart:326`)
/// WCAG AA 4.5:1 de sağlanır — `destructive`/`success`/`info` ≥ 4.5,
/// `warning` metin rengi olarak **kullanılmaz** (yalnızca ikon/çubuk/simge
/// dolgusu; `settings_page.dart:167-174`).
///
/// Neden ayrı değerler: tek bir hex hem açık hem koyu zeminde 4.5:1'i
/// sağlayamaz (koyu tema renkleri açık zeminde soluklaşıyor). Web parity'si
/// **koyu temada** birebir korunur; açık tema için ayrı tonlar tanımlanır.
abstract final class AppColors {
  // Web'in ana renklerine yakın Material 3 seed
  static const Color seed = Color(0xFF00C7B7); // CaloriX teal (demo rozeti rengi)

  // Semantik renkler — web `index.css` dark-mode HSL değerlerinin RGB karşılığı.
  //
  // !!! BU SABİTLER KOYU TEMA İÇİN SEÇİLMİŞTİR !!!
  // Açık temada semantik renk olarak kullanılmamalı; `Theme.of(context)
  // .colorScheme` üzerinden [semantic] okunmalıdır. Doğrudan
  // `AppColors.destructive` kullanan features kodları (A4 alanı) koyu temada
  // doğru, açık temada yetersiz kontrast verir — bu dosyadaki
  // [AppSemanticColors] sınıfı ikisini de doğru verir.
  static const Color success = Color(0xFF24C28C); // hsl(152 72% 46%)
  static const Color warning = Color(0xFFF5A623); // hsl(38 92% 50%)
  static const Color destructive = Color(0xFFE03131); // hsl(0 72% 51%)
  static const Color info = Color(0xFF3D9DF2); // hsl(210 100% 56%)

  // Makro grafik renkleri — web `--macro-*` (dark) değerleri.
  static const Color macroProtein = Color(0xFF4DADFF); // hsl(210 100% 60%)
  static const Color macroCarbs = Color(0xFFF7B84D); // hsl(38 95% 55%)
  static const Color macroFat = Color(0xFFF25D8A); // hsl(340 85% 58%)

  /// Açık tema semantik renkleri — açık zemin (`#F4FBF8`) üzerinde ≥ 3.0:1
  /// (metin olarak kullanılan yerlerde ≥ 4.5:1) sağlayan koyu tonlar.
  static const Color successLight = Color(0xFF1B7F5A);
  static const Color warningLight = Color(0xFFB26A00);
  static const Color destructiveLight = Color(0xFFC92A2A);
  static const Color infoLight = Color(0xFF1B6FB5);

  /// Koyu tema semantik renkleri — koyu zemin (`#0E1513`) üzerinde ≥ 3.0:1.
  /// Koyu temada web parity'si için [success]/[warning]/[destructive]/[info]
  /// değerleri de 3.0:1'i geçer (bkz. tablo) ama metin olarak kullanıldığında
  /// 4.5:1'i geçmeyen `warning` (1.57) için açık ton kullanılır.
  static const Color successDark = Color(0xFF5BE0AC);
  static const Color warningDark = Color(0xFFFFC46B);
  static const Color destructiveDark = Color(0xFFFF6B6B);
  static const Color infoDark = Color(0xFF7FC4FF);

  /// `Brightness` → semantik renk seti. [ThemeData] oluşturulurken
  /// `colorScheme` ile birlikte `extensions` altına eklenir; çağıran
  /// `Theme.of(context).extension<AppSemanticColors>()!` ile okur.
  static AppSemanticColors semantic(Brightness brightness) =>
      brightness == Brightness.dark ? darkPalette : lightPalette;

  /// Koyu tema paleti (web `index.css` ile aynı tonlar, hafifçe açıldı).
  static final AppSemanticColors darkPalette = AppSemanticColors(
    success: successDark,
    warning: warningDark,
    destructive: destructiveDark,
    info: infoDark,
    macroProtein: macroProtein,
    macroCarbs: macroCarbs,
    macroFat: macroFat,
  );

  /// Açık tema paleti (WCAG düzeltilmiş tonlar).
  static final AppSemanticColors lightPalette = AppSemanticColors(
    success: successLight,
    warning: warningLight,
    destructive: destructiveLight,
    info: infoLight,
    // Makro renkleri de aynı süzgeçten geçmeli: `0xFF4DADFF` açık zeminde
    // 2.29:1 → okunamıyor.
    macroProtein: infoLight,
    macroCarbs: warningLight,
    macroFat: const Color(0xFFB02E5E),
  );
}

/// Tema `Brightness`'ine göre seçilen semantik renkler.
///
/// `AppColors.destructive` gibi **sabit** renkler `ThemeMode.system`
/// açık temada kontrast eşiğini tutturamıyordu (`destructive` 4.30:1,
/// `warning` 1.93:1). Bu sınıf `ThemeData.extensions` üzerinden taşınır;
/// widget'lar sabiti değil `theme.semantic.destructive` okumalıdır.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.destructive,
    required this.info,
    required this.macroProtein,
    required this.macroCarbs,
    required this.macroFat,
  });

  final Color success;
  final Color warning;
  final Color destructive;
  final Color info;
  final Color macroProtein;
  final Color macroCarbs;
  final Color macroFat;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? destructive,
    Color? info,
    Color? macroProtein,
    Color? macroCarbs,
    Color? macroFat,
  }) =>
      AppSemanticColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        destructive: destructive ?? this.destructive,
        info: info ?? this.info,
        macroProtein: macroProtein ?? this.macroProtein,
        macroCarbs: macroCarbs ?? this.macroCarbs,
        macroFat: macroFat ?? this.macroFat,
      );

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      info: Color.lerp(info, other.info, t)!,
      macroProtein: Color.lerp(macroProtein, other.macroProtein, t)!,
      macroCarbs: Color.lerp(macroCarbs, other.macroCarbs, t)!,
      macroFat: Color.lerp(macroFat, other.macroFat, t)!,
    );
  }
}

/// `BuildContext`/`ThemeData` üzerinden semantik renklere kolay erişim.
extension AppSemanticColorsAccess on ThemeData {
  /// Mevcut palet — `AppTheme` tarafından `extensions` altına konur.
  AppSemanticColors get semantic =>
      extension<AppSemanticColors>() ??
      (brightness == Brightness.dark
          ? AppColors.darkPalette
          : AppColors.lightPalette);
}

class AppTheme {
  AppTheme._();

  /// `ThemeData` ağır bir nesne; `MaterialApp` her rebuild'da
  /// [light]/[dark] çağırıyordu (kayıtlı örnek: `app.dart:124-125`).
  /// `static final` ile bir kez üretilir — `ThemeData` değişmez (`const`
  /// olamaz: seed'den türetiliyor).
  static final ThemeData _light = _base(Brightness.light);
  static final ThemeData _dark = _base(Brightness.dark);

  static ThemeData light() => _light;

  static ThemeData dark() => _dark;

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      extensions: [AppColors.semantic(brightness)],
      visualDensity: VisualDensity.adaptivePlatformDensity,
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      // Kartlar: M3 surface tint gürültüsünü azalt, tek tip yuvarlatılmış köşe.
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      // Giriş alanları: yumuşak dolgu + outlined border (odak fix'inin
      // görsel güvenini de artırır).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Tema tercihi: dark varsayılan (web ile aynı), shared_preferences'ta kalıcı.
enum AppThemeMode { system, light, dark }

class ThemeModeNotifier extends Notifier<AppThemeMode> {
  static const _prefsKey = 'theme'; // web localStorage anahtarıyla aynı

  @override
  AppThemeMode build() {
    _load();
    return AppThemeMode.dark; // web varsayılanı: dark
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null) return;
    state = AppThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => AppThemeMode.dark,
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  ThemeMode get materialThemeMode => switch (state) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, AppThemeMode>(ThemeModeNotifier.new);
