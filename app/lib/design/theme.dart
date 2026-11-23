import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData buildEfTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: EfColors.warmPaper,
    colorScheme: const ColorScheme.light(
      primary: EfColors.emerald,
      onPrimary: EfColors.pureCard,
      secondary: EfColors.deepInk,
      onSecondary: EfColors.pureCard,
      surface: EfColors.pureCard,
      onSurface: EfColors.deepInk,
      error: EfColors.coral,
      onError: EfColors.pureCard,
      outline: EfColors.hairlineBorder,
    ),
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: EfColors.warmPaper,
      foregroundColor: EfColors.deepInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: EfTextStyles.display(20),
    ),
    cardTheme: CardThemeData(
      color: EfColors.pureCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EfRadii.lg),
        side: const BorderSide(color: EfColors.hairlineBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EfColors.pureCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EfRadii.md),
        borderSide: const BorderSide(color: EfColors.hairlineBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EfRadii.md),
        borderSide: const BorderSide(color: EfColors.hairlineBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EfRadii.md),
        borderSide: const BorderSide(color: EfColors.emerald, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(EfRadii.md),
        borderSide: const BorderSide(color: EfColors.coral),
      ),
      labelStyle: EfTextStyles.body(14, color: EfColors.mutedSlate),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: EfColors.emerald,
        foregroundColor: EfColors.pureCard,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EfRadii.md),
        ),
        textStyle: EfTextStyles.body(15,
            weight: FontWeight.w600, color: EfColors.pureCard),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: EfColors.deepInk,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: const BorderSide(color: EfColors.hairlineBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EfRadii.md),
        ),
        textStyle: EfTextStyles.body(15, weight: FontWeight.w600),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: EfColors.pureCard,
      indicatorColor: EfColors.emeraldTint,
      labelTextStyle: WidgetStateProperty.all(
        EfTextStyles.body(12, weight: FontWeight.w600),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: EfColors.pureCard,
      indicatorColor: EfColors.emeraldTint,
      selectedIconTheme: const IconThemeData(color: EfColors.emeraldDark),
      unselectedIconTheme: const IconThemeData(color: EfColors.mutedSlate),
      selectedLabelTextStyle: EfTextStyles.body(13,
          weight: FontWeight.w600, color: EfColors.emeraldDark),
      unselectedLabelTextStyle:
          EfTextStyles.body(13, color: EfColors.mutedSlate),
    ),
  );
}
