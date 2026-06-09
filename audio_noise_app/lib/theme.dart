import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Color palette
  static const bg       = Color(0xFF07060F);
  static const surface  = Color(0xFF0E0C1E);
  static const card     = Color(0xFF13112A);
  static const border   = Color(0xFF211E42);
  static const violet   = Color(0xFF8B5CF6);
  static const pink     = Color(0xFFEC4899);
  static const cyan     = Color(0xFF06B6D4);
  static const green    = Color(0xFF22C55E);
  static const amber    = Color(0xFFF59E0B);
  static const blue     = Color(0xFF3B82F6);
  static const textPrim = Color(0xFFF1F0FF);
  static const textDim  = Color(0xFF6B6894);
  static const textMid  = Color(0xFF9D9BC0);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.dark(
      primary: violet,
      secondary: pink,
      surface: surface,
      onPrimary: Colors.white,
      onSurface: textPrim,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: textPrim,
      displayColor: textPrim,
    ),
    cardTheme: const CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: violet,
      thumbColor: violet,
      inactiveTrackColor: border,
      overlayShape: SliderComponentShape.noOverlay,
      trackHeight: 3,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: violet,
      linearTrackColor: border,
    ),
  );
}
