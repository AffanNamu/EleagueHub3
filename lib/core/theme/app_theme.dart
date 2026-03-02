import 'package:flutter/material.dart';

/// Premium Sky/Navy app theme with enhanced glassmorphism
class AppTheme {
  // =========================
  // CORE BRAND COLORS
  // =========================

  // Deep Navy (Dark Mode) — UNCHANGED
  static const Color navyBg = Color(0xFF0A1D37);
  static const Color navyAccent = Color(0xFF00D4FF);

  // Premium Light Background Gradient (Bluish White)
  static const Color lightTop = Color(0xFFF8FBFF);
  static const Color lightMid = Color(0xFFEEF5FF);
  static const Color lightBottom = Color(0xFFEAF3FF);

  // Premium Text Tones (Better hierarchy)
  static const Color lightTextPrimary = Color(0xFF1A2B4C);
  static const Color lightTextSecondary = Color(0xFF5B6B8C);

  // Glass Layers (Light)
  static const Color _lightGlassFill = Color(0xBFFFFFFF); // ~75% frosted
  static const Color _lightGlassStroke = Color(0xCCFFFFFF); // soft white border

  // =========================
  // PUBLIC THEME ACCESSORS
  // =========================

  static ThemeData skyTheme() => _lightTheme();
  static ThemeData navyTheme() => _darkTheme();

  // =========================
  // LIGHT THEME (PREMIUM WHITE)
  // =========================

  static ThemeData _lightTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7AB6FF),
      brightness: Brightness.light,
    );

    final scheme = base.copyWith(
      primary: const Color(0xFF7AB6FF),
      secondary: const Color(0xFF7AB6FF),
      surface: Colors.transparent,
      background: lightTop,
      onSurface: lightTextPrimary,
      onBackground: lightTextPrimary,
      outline: Colors.white.withOpacity(0.7),
      outlineVariant: Colors.white.withOpacity(0.5),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: scheme,

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: lightTextPrimary,
        elevation: 0,
      ),

      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: lightTextPrimary),
        bodyMedium: TextStyle(color: lightTextPrimary),
        bodySmall: TextStyle(color: lightTextSecondary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.55),
        labelStyle: const TextStyle(color: lightTextSecondary),
        hintStyle: TextStyle(color: lightTextSecondary.withOpacity(0.7)),
        prefixIconColor: lightTextSecondary,
        suffixIconColor: lightTextSecondary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF7AB6FF),
            width: 1.5,
          ),
        ),
      ),

      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: Color(0xFF7AB6FF),
        selectionColor: Color(0x407AB6FF),
        selectionHandleColor: Color(0xFF7AB6FF),
      ),

      cardTheme: CardTheme(
        color: glassFill(Brightness.light),
        elevation: 0,
        shadowColor: const Color(0x667AB6FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: glassStroke(Brightness.light),
            width: 1,
          ),
        ),
      ),

      dividerColor: Colors.white.withOpacity(0.6),
    );
  }

  // =========================
  // DARK THEME — UNCHANGED
  // =========================

  static ThemeData _darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: navyBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: navyAccent,
        brightness: Brightness.dark,
        surface: navyBg,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardTheme(
        color: glassFill(Brightness.dark),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: glassStroke(Brightness.dark)),
        ),
      ),
    );
  }

  // =========================
  // GLASS HELPERS
  // =========================

  static Color glassFill(Brightness b) =>
      (b == Brightness.dark)
          ? const Color(0x1AFFFFFF)
          : _lightGlassFill;

  static Color glassStroke(Brightness b) =>
      (b == Brightness.dark)
          ? const Color(0x2EFFFFFF)
          : _lightGlassStroke;

  /// Premium background gradient
  static Gradient backgroundGradient(Brightness b) {
    if (b == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [navyBg, Color(0xFF07162A)],
      );
    }

    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        lightTop,
        lightMid,
        lightBottom,
      ],
    );
  }

  // =========================
  // STATUS COLORS (UNCHANGED)
  // =========================

  static Color statusColor(String status, Brightness b) {
    final s = status.trim().toLowerCase();

    switch (s) {
      case 'live':
        return const Color(0xFFE74C3C);
      case 'completed':
      case 'finished':
        return const Color(0xFF2ECC71);
      case 'cancelled':
      case 'canceled':
        return Colors.grey;
      default:
        return (b == Brightness.dark)
            ? Colors.white
            : lightTextPrimary;
    }
  }

  static List<Color> bubblePalette(Brightness b) {
    if (b == Brightness.dark) {
      return [
        navyBg,
        const Color(0xFF07162A),
        navyAccent.withOpacity(0.22),
        Colors.white.withOpacity(0.06),
      ];
    }

    return [
      lightTop,
      lightMid,
      const Color(0x667AB6FF),
      Colors.white.withOpacity(0.6),
    ];
  }
}
