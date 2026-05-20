import 'package:flutter/material.dart';

// ── Color palette ───────────────────────────────────────────────────────────
const kPrimary   = Color(0xFF065F46);  // deep forest green
const kSecondary = Color(0xFF059669);  // emerald
const kAccent    = Color(0xFFD97706);  // amber gold (CTAs)
const kRed       = Color(0xFFDC2626);
const kAmber     = Color(0xFFF59E0B);
const kBg        = Color(0xFFF0FDF4);
const kCard      = Colors.white;
const kText      = Color(0xFF111827);
const kMuted     = Color(0xFF6B7280);

// ── Shared decorations ───────────────────────────────────────────────────────
const kGradient = LinearGradient(
  colors: [kPrimary, kSecondary],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kBoxShadow = [
  BoxShadow(
    color: Color(0x14000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  ),
];

const kCardShadow = [
  BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  ),
];

// ── Premium ThemeData ────────────────────────────────────────────────────────
ThemeData appTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: kPrimary,
    onPrimary: Colors.white,
    secondary: kSecondary,
    onSecondary: Colors.white,
    error: kRed,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: kText,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    fontFamily: 'Roboto',

    // ── AppBar ───────────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'Roboto',
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),

    // ── Bottom navigation ────────────────────────────────────────────────────
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: kPrimary,
      unselectedItemColor: Color(0xFF9CA3AF),
      type: BottomNavigationBarType.fixed,
      elevation: 12,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelStyle: TextStyle(fontSize: 11),
    ),

    // ── ElevatedButton — amber gold CTA ─────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
        shadowColor: kAccent.withOpacity(0.4),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'Roboto',
        ),
      ),
    ),

    // ── OutlinedButton ───────────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),

    // ── TextButton ───────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kPrimary),
    ),

    // ── Inputs ───────────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kPrimary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kRed),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: kMuted),
      hintStyle: TextStyle(color: Colors.grey.shade400),
    ),

    // ── Cards ────────────────────────────────────────────────────────────────
    cardTheme: CardTheme(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    ),

    // ── Chips ────────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: kPrimary,
      side: const BorderSide(color: Color(0xFFE5E7EB)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
    ),

    // ── FAB ──────────────────────────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 4,
    ),

    // ── Dialog ───────────────────────────────────────────────────────────────
    dialogTheme: DialogTheme(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 24,
    ),

    // ── SnackBar ─────────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),

    // ── Divider ──────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: Color(0xFFF3F4F6),
      thickness: 1,
      space: 1,
    ),

    // ── Typography ───────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: kText),
      displayMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: kText),
      headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: kText),
      headlineMedium:TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kText),
      titleLarge:    TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText),
      titleMedium:   TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kText),
      bodyLarge:     TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: kText),
      bodyMedium:    TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: kText),
      labelLarge:    TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText),
      labelMedium:   TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kMuted),
    ),
  );
}
