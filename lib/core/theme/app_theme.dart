import 'package:flutter/material.dart';

/// App theme updated to support a clean premium light mode
/// and a polished dark mode using the same design language.
class AppTheme {
  // =========================
  // BRAND COLORS
  // =========================

  static const Color limeAccent = Color(0xFFB6FF00);
  static const Color limeAccentDark = Color(0xFF84CC16);
  static const Color darkText = Color(0xFF111827);
  static const Color mutedText = Color(0xFF6B7280);
  static const Color subtleBorder = Color(0xFFE5E7EB);
  static const Color searchBg = Color(0xFFF1F5F9);
  static const Color searchBorder = Color(0xFFE2E8F0);
  static const Color ownerRed = Color(0xFFEF4444);

  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardAlt = Color(0xFFF9FAFB);
  static const Color lightIconCircle = Color(0xFFECFCCB);
  static const Color lightNavBg = Color(0xFFFFFFFF);

  static const Color navyBg = Color(0xFF081120);
  static const Color navyBgSoft = Color(0xFF0F172A);
  static const Color darkCard = Color(0xFF182230);
  static const Color darkCardAlt = Color(0xFF222E3D);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkMutedText = Color(0xFF94A3B8);
  static const Color darkSearchBg = Color(0xFF111827);
  static const Color darkSearchBorder = Color(0xFF1F2937);
  static const Color darkNavBg = Color(0xFF0F172A);

  static ThemeData skyTheme() => _lightTheme();
  static ThemeData navyTheme() => _darkTheme();

  static ThemeData _lightTheme() {
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: limeAccent,
      onPrimary: darkText,
      secondary: limeAccentDark,
      onSecondary: Colors.white,
      error: ownerRed,
      onError: Colors.white,
      surface: lightCard,
      onSurface: darkText,
      outline: subtleBorder,
      outlineVariant: searchBorder,
      shadow: const Color(0x14000000),
      scrim: const Color(0x66000000),
      inverseSurface: darkText,
      onInverseSurface: Colors.white,
      inversePrimary: limeAccentDark,
      surfaceTint: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: lightBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBg,
        foregroundColor: darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shadowColor: const Color(0x12000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: subtleBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: searchBg,
        hintStyle: const TextStyle(
          color: mutedText,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: const TextStyle(
          color: mutedText,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: mutedText,
        suffixIconColor: mutedText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: searchBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: limeAccentDark,
            width: 1.4,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: searchBorder),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: limeAccent,
        foregroundColor: darkText,
        elevation: 10,
        focusElevation: 12,
        hoverElevation: 12,
        highlightElevation: 14,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightNavBg,
        selectedItemColor: limeAccentDark,
        unselectedItemColor: Color(0xFF9CA3AF),
        selectedIconTheme: IconThemeData(size: 24),
        unselectedIconTheme: IconThemeData(size: 24),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      dividerColor: subtleBorder,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: mutedText,
          fontWeight: FontWeight.w400,
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: limeAccentDark,
        selectionColor: Color(0x66B6FF00),
        selectionHandleColor: limeAccentDark,
      ),
    );
  }

  static ThemeData _darkTheme() {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: limeAccent,
      onPrimary: darkText,
      secondary: limeAccentDark,
      onSecondary: Colors.white,
      error: ownerRed,
      onError: Colors.white,
      surface: darkCard,
      onSurface: Colors.white,
      outline: darkBorder,
      outlineVariant: const Color(0xFF243244),
      shadow: const Color(0x66000000),
      scrim: const Color(0x99000000),
      inverseSurface: Colors.white,
      onInverseSurface: darkText,
      inversePrimary: limeAccentDark,
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: navyBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: navyBg,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shadowColor: const Color(0x66000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSearchBg,
        hintStyle: const TextStyle(
          color: darkMutedText,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: const TextStyle(
          color: darkMutedText,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: darkMutedText,
        suffixIconColor: darkMutedText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: darkSearchBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: limeAccentDark,
            width: 1.4,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: darkSearchBorder),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: limeAccent,
        foregroundColor: darkText,
        elevation: 12,
        focusElevation: 14,
        hoverElevation: 14,
        highlightElevation: 16,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkNavBg,
        selectedItemColor: limeAccentDark,
        unselectedItemColor: Color(0xFF9CA3AF),
        selectedIconTheme: IconThemeData(size: 24),
        unselectedIconTheme: IconThemeData(size: 24),
        type: BottomNavigationBarType.fixed,
        elevation: 10,
      ),
      dividerColor: darkBorder,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: TextStyle(
          color: darkMutedText,
          fontWeight: FontWeight.w400,
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: limeAccent,
        selectionColor: Color(0x66B6FF00),
        selectionHandleColor: limeAccent,
      ),
    );
  }

  static Gradient backgroundGradient(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF081120),
          Color(0xFF0B1324),
          Color(0xFF0F172A),
        ],
      );
    }

    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFFFFFFF),
        Color(0xFFF8FAFC),
        Color(0xFFF1F5F9),
      ],
    );
  }

  static Gradient leagueCardGradient(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF253243),
          Color(0xFF1B2635),
        ],
      );
    }

    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFFFFFFFF),
        Color(0xFFF9FAFB),
      ],
    );
  }

  static Color cardColor(Brightness brightness) {
    return brightness == Brightness.dark ? darkCard : lightCard;
  }

  static Color cardBorder(Brightness brightness) {
    return brightness == Brightness.dark ? darkBorder : subtleBorder;
  }

  static Color primaryText(Brightness brightness) {
    return brightness == Brightness.dark ? Colors.white : darkText;
  }

  static Color secondaryText(Brightness brightness) {
    return brightness == Brightness.dark ? darkMutedText : mutedText;
  }

  static Color searchBackground(Brightness brightness) {
    return brightness == Brightness.dark ? darkSearchBg : searchBg;
  }

  static Color searchOutline(Brightness brightness) {
    return brightness == Brightness.dark ? darkSearchBorder : searchBorder;
  }

  static Color tabInactiveBackground(Brightness brightness) {
    return brightness == Brightness.dark
        ? const Color(0xFF1F2937)
        : const Color(0xFFE5E7EB);
  }

  static Color tabInactiveText(Brightness brightness) {
    return brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF6B7280);
  }

  static Color iconCircleBackground(Brightness brightness) {
    return brightness == Brightness.dark
        ? const Color(0xFF253243)
        : lightIconCircle;
  }

  static List<BoxShadow> fabGlow(Brightness brightness) {
    return [
      BoxShadow(
        color: (brightness == Brightness.dark
                ? limeAccent
                : limeAccentDark)
            .withOpacity(0.28),
        blurRadius: 24,
        spreadRadius: 2,
        offset: const Offset(0, 10),
      ),
    ];
  }

  static List<BoxShadow> softCardShadow(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 24,
          offset: Offset(0, 12),
        ),
      ];
    }

    return const [
      BoxShadow(
        color: Color(0x140F172A),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
    ];
  }

  static Color glassFill(Brightness b) {
    return b == Brightness.dark
        ? const Color(0xCC182230)
        : const Color(0xF2FFFFFF);
  }

  static Color glassStroke(Brightness b) {
    return b == Brightness.dark
        ? const Color(0xFF334155)
        : const Color(0xFFE5E7EB);
  }

  static Color statusColor(String status, Brightness b) {
    final s = status.trim().toLowerCase();

    switch (s) {
      case 'live':
        return const Color(0xFFE74C3C);
      case 'completed':
      case 'finished':
        return const Color(0xFF22C55E);
      case 'cancelled':
      case 'canceled':
        return Colors.grey;
      default:
        return primaryText(b);
    }
  }

  static List<Color> bubblePalette(Brightness b) {
    if (b == Brightness.dark) {
      return [
        const Color(0x140F172A),
        const Color(0x1AB6FF00),
        const Color(0x10111827),
        const Color(0x12334155),
      ];
    }

    return [
      const Color(0x14B6FF00),
      const Color(0x10D9F99D),
      const Color(0x12E2E8F0),
      const Color(0x16FFFFFF),
    ];
  }
}