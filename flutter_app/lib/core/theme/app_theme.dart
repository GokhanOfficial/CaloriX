import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Web uygulamasıyla uyumlu tema paleti (tailwind dark-default).
abstract final class AppColors {
  // Web'in ana renklerine yakın Material 3 seed
  static const Color seed = Color(0xFF00C7B7); // CaloriX teal (demo rozeti rengi)

  // Semantik renkler — web `index.css` dark-mode HSL değerlerinin RGB karşılığı.
  static const Color success = Color(0xFF24C28C); // hsl(152 72% 46%)
  static const Color warning = Color(0xFFF5A623); // hsl(38 92% 50%)
  static const Color destructive = Color(0xFFE03131); // hsl(0 72% 51%)
  static const Color info = Color(0xFF3D9DF2); // hsl(210 100% 56%)

  // Makro grafik renkleri — web `--macro-*` (dark) değerleri.
  static const Color macroProtein = Color(0xFF4DADFF); // hsl(210 100% 60%)
  static const Color macroCarbs = Color(0xFFF7B84D); // hsl(38 95% 55%)
  static const Color macroFat = Color(0xFFF25D8A); // hsl(340 85% 58%)
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
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
