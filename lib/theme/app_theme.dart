import 'package:flutter/material.dart';
import '../services/app_prefs.dart';

// ── Brand purple palette ──────────────────────────────────────────────────────
class AppColors {
  static const Color background   = Color(0xFF0C0A14);
  static const Color primary      = Color(0xFF8B5CF6);
  static const Color primaryDark  = Color(0xFF7C3AED);
  static const Color yellow       = Color(0xFFA78BFA);
  static const Color yellowDark   = Color(0xFF7C3AED);
  static const Color surface      = Color(0xFF151020);
  static const Color surfaceLight = Color(0xFF221A35);
  static const Color cardBg       = Color(0xFF1A1428);
  static const Color white        = Color(0xFFF5F3FF);
  static const Color grey         = Color(0xFF9B8BB8);
  static const Color greyLight    = Color(0xFFC4B5FD);
}

class AppColorsLight {
  static const Color background   = Color(0xFFF8F6FF);
  static const Color primary      = Color(0xFF7C3AED);
  static const Color yellow       = Color(0xFF7C3AED);
  static const Color surface      = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF3EEFF);
  static const Color cardBg       = Color(0xFFFFFFFF);
  static const Color white        = Color(0xFF1E1B2E);
  static const Color grey         = Color(0xFF6B6280);
  static const Color greyLight    = Color(0xFF9CA3AF);
}

/// Shared gradients for splash, login, and hero sections.
class AppGradients {
  static const splash = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFFA78BFA), Color(0xFFEDE9FE)],
    stops: [0.0, 0.45, 1.0],
  );

  static const primaryButton = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
  );

  static const heroLight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
  );

  static const heroDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2E1065), Color(0xFF1A1428)],
  );

  static LinearGradient hero(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? heroDark : heroLight;
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
  Color get borderColor => isDark ? const Color(0xFF2D2640) : const Color(0xFFE9E5F5);
}

// ── Themes ────────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.background : AppColorsLight.background;
    final card = isDark ? AppColors.cardBg : AppColorsLight.cardBg;
    final primary = isDark ? AppColors.primary : AppColorsLight.primary;
    final text = isDark ? AppColors.white : AppColorsLight.white;
    final border = isDark ? const Color(0xFF2D2640) : const Color(0xFFE9E5F5);

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      cardColor: card,
      dividerColor: border,
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: Colors.white,
        secondary: const Color(0xFFA78BFA),
        onSecondary: Colors.white,
        surface: isDark ? AppColors.surface : AppColorsLight.surface,
        onSurface: text,
        error: const Color(0xFFEF4444),
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? AppColors.surface : AppColorsLight.surface,
        foregroundColor: text,
        iconTheme: IconThemeData(color: text),
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: isDark ? 0 : 2,
        shadowColor: const Color(0xFF7C3AED).withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      iconTheme: IconThemeData(color: text),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: text, height: 1.45),
        bodyMedium: TextStyle(color: text, height: 1.4),
        bodySmall: TextStyle(color: isDark ? AppColors.grey : AppColorsLight.grey),
        titleMedium: TextStyle(color: text, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 22),
        headlineSmall: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 26),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.surfaceLight : AppColorsLight.surfaceLight,
        hintStyle: TextStyle(color: isDark ? AppColors.grey : AppColorsLight.greyLight),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(primary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? primary.withOpacity(0.35)
                : isDark ? AppColors.surfaceLight : AppColorsLight.surfaceLight),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surface : AppColorsLight.surface,
        selectedItemColor: primary,
        unselectedItemColor: isDark ? AppColors.grey : AppColorsLight.greyLight,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: isDark ? AppColors.grey : AppColorsLight.grey,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    try {
      final prefs = await AppPrefs.instance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'light') {
        _mode = ThemeMode.light;
      } else if (saved == 'dark') {
        _mode = ThemeMode.dark;
      } else {
        _mode = ThemeMode.system;
      }
    } catch (_) {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await AppPrefs.instance();
      final value = switch (_mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await prefs.setString(_prefKey, value);
    } catch (_) {}
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
