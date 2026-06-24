import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Dark palette ──────────────────────────────────────────────────────────────
class AppColors {
  static const Color background   = Color(0xFF050F0A);
  static const Color primary      = Color(0xFF00E676);
  static const Color primaryDark  = Color(0xFF00C853);
  static const Color yellow       = Color(0xFF00E676);
  static const Color yellowDark   = Color(0xFF00C853);
  static const Color surface      = Color(0xFF0D1F15);
  static const Color surfaceLight = Color(0xFF122B1C);
  static const Color cardBg       = Color(0xFF0C1A11);
  static const Color white        = Color(0xFFFFFFFF);
  static const Color grey         = Color(0xFF6B8A76);
  static const Color greyLight    = Color(0xFF9DB8A6);
}

// ── Light palette ─────────────────────────────────────────────────────────────
class AppColorsLight {
  static const Color background   = Color(0xFFF9FAFB);
  static const Color primary      = Color(0xFF22C55E);
  static const Color yellow       = Color(0xFF22C55E);
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF3F4F6);
  static const Color cardBg       = Color(0xFFFFFFFF);
  static const Color white        = Color(0xFF111827);
  static const Color grey         = Color(0xFF6B7280);
  static const Color greyLight    = Color(0xFF9CA3AF);
}

// ── Context helpers ───────────────────────────────────────────────────────────
extension ThemeCtx on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get bgColor     => isDark ? AppColors.background   : AppColorsLight.background;
  Color get cardColor   => isDark ? AppColors.cardBg       : AppColorsLight.cardBg;
  Color get headerColor => isDark ? AppColors.surface      : AppColorsLight.surface;
  Color get surfColor   => isDark ? AppColors.surfaceLight : AppColorsLight.surfaceLight;
  Color get textColor   => isDark ? AppColors.white        : AppColorsLight.white;
  Color get greyColor   => isDark ? AppColors.grey         : AppColorsLight.grey;
  Color get greyLColor  => isDark ? AppColors.greyLight    : AppColorsLight.greyLight;
  Color get accentColor => isDark ? AppColors.yellow       : AppColorsLight.yellow;
  Color get borderColor => isDark ? const Color(0xFF2A2A2A): const Color(0xFFE5E7EB);
}

// ── Themes ────────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.background : AppColorsLight.background;
    final card = isDark ? AppColors.cardBg : AppColorsLight.cardBg;
    final primary = isDark ? AppColors.yellow : AppColorsLight.yellow;
    final text = isDark ? AppColors.white : AppColorsLight.white;
    final border = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB);

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      cardColor: card,
      dividerColor: border,
      fontFamily: 'sans-serif',
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: isDark ? AppColors.background : Colors.white,
        secondary: primary,
        onSecondary: isDark ? AppColors.background : Colors.white,
        surface: isDark ? AppColors.surface : AppColorsLight.surface,
        onSurface: text,
        error: const Color(0xFFEF4444),
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: isDark ? AppColors.surface : AppColorsLight.surface,
        foregroundColor: text,
        iconTheme: IconThemeData(color: text),
      ),
      iconTheme: IconThemeData(color: text),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: text),
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: isDark ? AppColors.grey : AppColorsLight.grey),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.bold),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceLight : AppColorsLight.surfaceLight,
        hintStyle: TextStyle(color: isDark ? AppColors.grey : AppColorsLight.greyLight),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: isDark ? AppColors.background : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(primary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? primary.withOpacity(0.4)
                : isDark ? AppColors.surfaceLight : AppColorsLight.surfaceLight),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surface : AppColorsLight.surface,
        selectedItemColor: primary,
        unselectedItemColor: isDark ? AppColors.greyLight : AppColorsLight.greyLight,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: isDark ? AppColors.grey : AppColorsLight.grey,
        indicatorColor: primary,
      ),
    );
  }
}

// ── Theme notifier ────────────────────────────────────────────────────────────
class ThemeNotifier extends ChangeNotifier {
  static const _prefKey = 'theme_mode';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved == 'light') {
      _mode = ThemeMode.light;
    } else if (saved == 'dark') {
      _mode = ThemeMode.dark;
    } else {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final value = switch (_mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_prefKey, value);
  }

  void setLight() {
    _mode = ThemeMode.light;
    _persist();
    notifyListeners();
  }

  void setDark() {
    _mode = ThemeMode.dark;
    _persist();
    notifyListeners();
  }

  void setSystem() {
    _mode = ThemeMode.system;
    _persist();
    notifyListeners();
  }

  void toggle() {
    if (_mode == ThemeMode.dark) {
      setLight();
    } else {
      setDark();
    }
  }
}

final themeNotifier = ThemeNotifier();
