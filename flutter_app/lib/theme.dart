import 'package:flutter/material.dart';

// ── Color palette (Serif Ledger — gold accent) ───────────────────────────────
// kPrimary is the app-wide CHROME accent (buttons, tabs, nav, FAB, headers).
// Serif Ledger uses gold. kSecondary (emerald) + kRed stay for money semantics.
const kPrimary   = Color(0xFFA16207);   // gold (was deep forest green)
const kSecondary = Color(0xFF059669);   // emerald — POSITIVE money only
const kAccent    = Color(0xFFA16207);   // gold — CTAs (unified with primary)
const kRed       = Color(0xFFDC2626);   // NEGATIVE money
const kAmber     = Color(0xFFF59E0B);
const kBg        = Color(0xFFF3F4F6);
const kCard      = Colors.white;
const kText      = Color(0xFF111827);
const kMuted     = Color(0xFF6B7280);
const kSerif     = 'serif';             // Noto Serif on Android — premium headings

// ── Shared decorations ───────────────────────────────────────────────────────
const kGradient = LinearGradient(
  colors: [Color(0xFFB8860B), Color(0xFF8A5A09)], // goldenrod → deep gold
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const kBoxShadow = [
  BoxShadow(
    color: Color(0x18000000),
    blurRadius: 16,
    offset: Offset(0, 4),
  ),
];

const kCardShadow = [
  BoxShadow(
    color: Color(0x0D000000),
    blurRadius: 10,
    offset: Offset(0, 2),
  ),
];

// ── Premium ThemeData ────────────────────────────────────────────────────────
ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: Brightness.light,
  ).copyWith(
    primary: kPrimary,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFD1FAE5),
    onPrimaryContainer: kPrimary,
    secondary: kSecondary,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFD1FAE5),
    onSecondaryContainer: kSecondary,
    tertiary: kAccent,
    onTertiary: Colors.white,
    error: kRed,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: kText,
    outline: const Color(0xFFE5E7EB),
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
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.w800,
        fontFamily: kSerif,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: Colors.white),
      actionsIconTheme: IconThemeData(color: Colors.white),
    ),

    // ── Bottom navigation ────────────────────────────────────────────────────
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: kPrimary,
      unselectedItemColor: Color(0xFF9CA3AF),
      type: BottomNavigationBarType.fixed,
      elevation: 16,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      unselectedLabelStyle: TextStyle(fontSize: 11),
    ),

    // ── ElevatedButton — amber gold CTA ─────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE5E7EB),
        disabledForegroundColor: kMuted,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
        shadowColor: Color(0x66D97706),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'Roboto',
          letterSpacing: 0.2,
        ),
      ),
    ),

    // ── OutlinedButton ───────────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
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
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kRed, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: kMuted, fontSize: 14),
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
      prefixIconColor: kMuted,
    ),

    // ── Cards ────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.08),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),

    // ── FAB ──────────────────────────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),

    // ── Dialog ───────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 24,
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: kText,
        fontFamily: 'Roboto',
      ),
    ),

    // ── SnackBar ─────────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),

    // ── Divider ──────────────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: Color(0xFFF3F4F6),
      thickness: 1,
      space: 1,
    ),

    // ── ListTile ─────────────────────────────────────────────────────────────
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 8,
    ),

    // ── Bottom sheet ─────────────────────────────────────────────────────────
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
    ),

    // ── Typography ───────────────────────────────────────────────────────────
    textTheme: const TextTheme(
      // Headings use the serif face for the Serif Ledger feel; body stays sans.
      displayLarge:   TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: kText, letterSpacing: -0.5, fontFamily: kSerif),
      displayMedium:  TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kText, fontFamily: kSerif),
      headlineLarge:  TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kText, fontFamily: kSerif),
      headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kText, fontFamily: kSerif),
      titleLarge:     TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText),
      titleMedium:    TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kText),
      bodyLarge:      TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: kText),
      bodyMedium:     TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: kText),
      labelLarge:     TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText),
      labelMedium:    TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kMuted),
      labelSmall:     TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: kMuted),
    ),
  );
}

// ── Reusable decoration helpers ───────────────────────────────────────────────
BoxDecoration kChipDecoration({required bool active, Color? color}) => BoxDecoration(
  color: active ? (color ?? kPrimary) : Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: active ? (color ?? kPrimary) : const Color(0xFFE5E7EB)),
);

BoxDecoration kSurfaceDecoration({double radius = 16}) => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(radius),
  boxShadow: kCardShadow,
);
