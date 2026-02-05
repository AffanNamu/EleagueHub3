import 'package:flutter/material.dart';

/// Core Sky/Navy app theme with glassmorphism helpers
class AppTheme {
  // =========================
  // CORE BRAND COLORS
  // =========================

  // Deep Navy (Dark Mode) — UNCHANGED
  static const Color navyBg = Color(0xFF0A1D37);
  static const Color navyAccent = Color(0xFF00D4FF);

  // Sky (Light Mode) — keep as ACCENT only (NOT background)
  static const Color skyTop = Color(0xFF40C4FF);
  static const Color skyBottom = Color(0xFF81D4FA);

  // Light Mode Surfaces (premium off-white; not pure white)
  static const Color lightSurface = Color(0xFFFAFBFC);
  static const Color lightSurfaceAlt = Color(0xFFF3F6FA);

  // Light-mode glass (premium frosted white; readable with navy/slate text)
  static const Color _lightGlassFill = Color(0xBFFFFFFF); // ~75% frosted white
  static const Color _lightGlassStroke = Color(0x1F0A1D37); // subtle navy edge

  // =========================
  // PUBLIC THEME ACCESSORS
  // =========================

  static ThemeData skyTheme() => _lightTheme();
  static ThemeData navyTheme() => _darkTheme();

  // =========================
  // LIGHT THEME (OFF-WHITE BACKGROUND)
  // =========================

  static ThemeData _lightTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: skyTop,
      brightness: Brightness.light,
    );

    final scheme = base.copyWith(
      primary: skyTop,
      secondary: skyTop,
      surface: lightSurface,
      background: lightSurface,
      onSurface: navyBg,
      onBackground: navyBg,
      outline: navyBg.withOpacity(0.18),
      outlineVariant: navyBg.withOpacity(0.10),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightSurface,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: navyBg,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withOpacity(0.04),
        labelStyle: TextStyle(color: navyBg.withOpacity(0.75)),
        hintStyle: TextStyle(color: navyBg.withOpacity(0.55)),
        prefixIconColor: navyBg.withOpacity(0.70),
        suffixIconColor: navyBg.withOpacity(0.70),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: navyBg.withOpacity(0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: skyTop.withOpacity(0.85), width: 1.4),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: skyTop,
        selectionColor: skyTop.withOpacity(0.25),
        selectionHandleColor: skyTop,
      ),
      cardTheme: CardTheme(
        color: glassFill(Brightness.light),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: glassStroke(Brightness.light)),
        ),
      ),
      dividerColor: navyBg.withOpacity(0.10),
    );
  }

  // =========================
  // DARK (NAVY) THEME — UNCHANGED
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIconColor: Colors.white70,
        suffixIconColor: Colors.white70,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: navyAccent, width: 1.4),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: navyAccent,
        selectionColor: navyAccent.withOpacity(0.25),
        selectionHandleColor: navyAccent,
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
  // GLASSMORPHISM HELPERS
  // =========================

  /// Glass fill color (semi-transparent)
  static Color glassFill(Brightness b) =>
      (b == Brightness.dark) ? const Color(0x1AFFFFFF) : _lightGlassFill;

  /// Glass stroke color (border)
  static Color glassStroke(Brightness b) =>
      (b == Brightness.dark) ? const Color(0x2EFFFFFF) : _lightGlassStroke;

  /// Background gradient for entire scaffold
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
        lightSurface,
        lightSurfaceAlt,
      ],
    );
  }

  // =========================
  // DOMAIN COLORS
  // =========================

  /// Badge / status color helper
  static Color statusColor(String status, Brightness b) {
    final s = status.trim().toLowerCase();

    switch (s) {
      case 'open':
      case 'recruiting':
        return (b == Brightness.dark) ? navyAccent : navyBg;

      case 'in progress':
      case 'ongoing':
        return const Color(0xFFF1C40F);

      case 'live':
        return const Color(0xFFE74C3C);

      case 'completed':
      case 'finished':
        return const Color(0xFF2ECC71);

      case 'disputed':
        return const Color(0xFF9B59B6);

      case 'cancelled':
      case 'canceled':
        return Colors.grey;

      default:
        return (b == Brightness.dark) ? Colors.white : navyBg;
    }
  }

  /// Bubble palette for animated backgrounds
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
      lightSurface,
      lightSurfaceAlt,
      skyTop.withOpacity(0.10),
      const Color(0xFFB3E5FC),
    ];
  }
}
