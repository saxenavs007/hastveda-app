// HastVeda Design System — derived from official logo
// Logo: black background, gold palm, cyan/blue AI accents, gold "H" emblem, silver+gold wordmark

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand Core (Dark) ────────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0A0A0F);
  static const Color surfaceDark = Color(0xFF12121A);
  static const Color surfaceElevated = Color(0xFF1A1A26);
  static const Color outlineDark = Color(0xFF2A2A3A);

  // ── Brand Core (Light) — Confetti: cream, saffron, festive warmth ────────
  static const Color backgroundLight = Color(0xFFFFF6E8);
  static const Color surfaceLight = Color(0xFFFFFDF8);
  static const Color surfaceElevatedLight = Color(0xFFFFF1D4);
  static const Color outlineLight = Color(0xFFE8D3B0);

  // ── Gold Accent (Premium / Highlight) ───────────────────────────────────
  static const Color gold = Color(0xFFD4A843);
  static const Color goldLight = Color(0xFFEFC96A);
  static const Color goldMuted = Color(0xFF3A2E10);
  static const Color goldMutedLight = Color(0xFFFFF8E7);

  // ── Cyan / Blue AI Accent ───────────────────────────────────────────────
  static const Color cyan = Color(0xFF00C8E0);
  static const Color cyanMuted = Color(0xFF001E24);
  static const Color cyanMutedLight = Color(0xFFE0FAFF);

  // ── Deep Purple Brand (dark-mode tertiary only) ──────────────────────────
  static const Color deepPurple = Color(0xFF6B4FBB);
  static const Color purpleMuted = Color(0xFF1E1530);

  // ── Confetti (light mode) ────────────────────────────────────────────────
  // Saffron, marigold, coral, and maroon on a cream ground — festive, Vedic.
  static const Color confetti = Color(0xFFC2410C);
  static const Color confettiDeep = Color(0xFF8C2F39);
  static const Color confettiMarigold = Color(0xFFE6A23C);
  static const Color confettiCoral = Color(0xFFD4526E);
  static const Color purpleMutedLight = Color(0xFFFFE8C2);

  // ── Primary / Secondary ─────────────────────────────────────────────────
  static const Color primary = gold;
  static const Color primaryLight = goldLight;
  static const Color primaryContainer = goldMuted;

  static const Color secondary = cyan;
  static const Color secondaryContainer = cyanMuted;

  // ── Text (Dark) ──────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF0EDE8);
  static const Color textSecondary = Color(0xFF9A96A8);
  static const Color textMuted = Color(0xFF5A5870);

  // ── Text (Light) ─────────────────────────────────────────────────────────
  static const Color textPrimaryLight = Color(0xFF3A2418);
  static const Color textSecondaryLight = Color(0xFF7A5340);
  static const Color textMutedLight = Color(0xFFA8846A);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF2ECC8A);
  static const Color successContainer = Color(0xFF0A2A1E);
  static const Color warning = Color(0xFFD4A843);
  static const Color warningContainer = Color(0xFF2A1E08);
  static const Color error = Color(0xFFE05555);
  static const Color errorContainer = Color(0xFF2A0A0A);
  static const Color disabled = Color(0xFF3A3A4A);

  // ── Gradient helpers ─────────────────────────────────────────────────────
  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFD4A843), Color(0xFFEFC96A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF00C8E0), Color(0xFF0090A8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient purpleGoldGradient = LinearGradient(
    colors: [Color(0xFF6B4FBB), Color(0xFFD4A843)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkSurfaceGradient = LinearGradient(
    colors: [Color(0xFF12121A), Color(0xFF1A1A26)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient lightSurfaceGradient = LinearGradient(
    colors: [Color(0xFFFFFDF8), Color(0xFFFFF1D4)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient purpleGradientLight = LinearGradient(
    colors: [Color(0xFFC2410C), Color(0xFFD4526E), Color(0xFF8C2F39)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── ThemeData ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme => _buildDarkTheme();
  static ThemeData get lightTheme => _buildLightTheme();

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        onPrimary: Color(0xFF0A0A0F),
        primaryContainer: goldMuted,
        onPrimaryContainer: goldLight,
        secondary: cyan,
        onSecondary: Color(0xFF0A0A0F),
        secondaryContainer: cyanMuted,
        onSecondaryContainer: cyan,
        tertiary: deepPurple,
        onTertiary: Colors.white,
        surface: surfaceDark,
        onSurface: textPrimary,
        surfaceContainerHighest: surfaceElevated,
        onSurfaceVariant: textSecondary,
        error: error,
        onError: Colors.white,
        outline: outlineDark,
        outlineVariant: Color(0xFF1E1E2E),
      ),
      scaffoldBackgroundColor: backgroundDark,
      textTheme: _buildTextTheme(textPrimary, textSecondary, textMuted),
      appBarTheme: AppBarThemeData(
        backgroundColor: surfaceDark,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outlineDark, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceElevated,
        selectedColor: goldMuted,
        labelStyle: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: gold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: GoogleFonts.outfit(fontSize: 14, color: textMuted),
        labelStyle: GoogleFonts.outfit(fontSize: 14, color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: gold,
          foregroundColor: const Color(0xFF0A0A0F),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          side: const BorderSide(color: gold),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: gold,
          textStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: outlineDark, thickness: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: gold,
        unselectedItemColor: textMuted,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceDark,
        indicatorColor: goldMuted,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: gold,
            );
          }
          return GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: gold, size: 22);
          }
          return const IconThemeData(color: textMuted, size: 22);
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return gold;
          return textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return goldMuted;
          return outlineDark;
        }),
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: confetti,
        onPrimary: Colors.white,
        primaryContainer: purpleMutedLight,
        onPrimaryContainer: confettiDeep,
        secondary: gold,
        onSecondary: Colors.white,
        secondaryContainer: goldMutedLight,
        onSecondaryContainer: Color(0xFF5A3A00),
        tertiary: cyan,
        onTertiary: Colors.white,
        surface: surfaceLight,
        onSurface: textPrimaryLight,
        surfaceContainerHighest: surfaceElevatedLight,
        onSurfaceVariant: textSecondaryLight,
        error: error,
        onError: Colors.white,
        outline: outlineLight,
        outlineVariant: Color(0xFFF3E0C0),
      ),
      scaffoldBackgroundColor: backgroundLight,
      textTheme: _buildTextTheme(
        textPrimaryLight,
        textSecondaryLight,
        textMutedLight,
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: surfaceLight,
        foregroundColor: textPrimaryLight,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        shadowColor: outlineLight,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimaryLight,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        shadowColor: const Color(0x1AC2410C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outlineLight, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceElevatedLight,
        selectedColor: purpleMutedLight,
        labelStyle: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textPrimaryLight,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: surfaceElevatedLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: confetti, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: GoogleFonts.outfit(fontSize: 14, color: textMutedLight),
        labelStyle: GoogleFonts.outfit(fontSize: 14, color: textSecondaryLight),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: confetti,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: confetti,
          side: const BorderSide(color: confetti),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: confetti,
          textStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: outlineLight, thickness: 1),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceLight,
        selectedItemColor: confetti,
        unselectedItemColor: textMutedLight,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceLight,
        indicatorColor: purpleMutedLight,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: confetti,
            );
          }
          return GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: textMutedLight,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: confetti, size: 22);
          }
          return const IconThemeData(color: textMutedLight, size: 22);
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return confetti;
          return textMutedLight;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return purpleMutedLight;
          return outlineLight;
        }),
      ),
    );
  }

  static TextTheme _buildTextTheme(
    Color primary,
    Color secondary,
    Color muted,
  ) {
    return GoogleFonts.outfitTextTheme(
      TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: primary,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: secondary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: primary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: secondary,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: muted,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: secondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: muted,
        ),
      ),
    );
  }

  // ── Convenience helpers for theme-aware colors ────────────────────────────
  static Color bgColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? backgroundDark
        : backgroundLight;
  }

  static Color surfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? surfaceDark
        : surfaceLight;
  }

  static Color surfaceElevatedColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? surfaceElevated
        : surfaceElevatedLight;
  }

  static Color outlineColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? outlineDark
        : outlineLight;
  }

  static Color textPrimaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? textPrimary
        : textPrimaryLight;
  }

  static Color textSecondaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? textSecondary
        : textSecondaryLight;
  }

  static Color textMutedColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? textMuted
        : textMutedLight;
  }

  static Color primaryBrandColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? gold : confetti;
  }

  static Color goldMutedColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? goldMuted
        : goldMutedLight;
  }

  static Color purpleMutedColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? purpleMuted
        : purpleMutedLight;
  }

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}
