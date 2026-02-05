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
  // Used for backgrounds/surfaces to replace sky-blue usage.
  static const Color lightSurface = Color(0xFFFAFBFC);
  static const Color lightSurfaceAlt = Color(0xFFF3F6FA);

  // =========================
  // PUBLIC THEME ACCESSORS
  // =========================

  static ThemeData skyTheme() => _lightTheme();
  static ThemeData navyTheme() => _darkTheme();

  // =========================
  // LIGHT THEME (OFF-WHITE SURFACES)
  // =========================

  static ThemeData _lightTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: skyTop, // keep brand accent seed
      brightness: Brightness.light,
    );

    // Keep this compatible across Flutter versions by only using widely available fields.
    final scheme = base.copyWith(
      primary: skyTop,
      secondary: skyTop,
      surface: lightSurface,
      background: lightSurface,
      onSurface: navyBg,
      onBackground: navyBg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Replace sky-blue scaffold background with premium off-white.
      scaffoldBackgroundColor: lightSurface,
      colorScheme: scheme,

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: navyBg,
        elevation: 0,
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
      (b == Brightness.dark) ? const Color(0x1AFFFFFF) : const Color(0x26FFFFFF);

  /// Glass stroke color (border)
  static Color glassStroke(Brightness b) =>
      (b == Brightness.dark) ? const Color(0x2EFFFFFF) : const Color(0x33FFFFFF);

  /// Background gradient for entire scaffold
  ///
  /// - Dark: navy gradient (UNCHANGED)
  /// - Light: off-white gradient (replaces sky-blue background usage)
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
  ///
  /// Light mode uses subtle, premium tints (no sky-blue full-screen background).
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
