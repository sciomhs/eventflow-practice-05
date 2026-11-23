import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// EventFlow Design System Tokens (Stitch-calibrated).
/// All colors in the app MUST reference these tokens; no raw hex literals elsewhere.
abstract final class EfColors {
  static const Color warmPaper = Color(0xFFFAF7F2);
  static const Color pureCard = Color(0xFFFFFFFF);
  static const Color warmStone = Color(0xFFF1ECE2);
  static const Color deepInk = Color(0xFF1C1B18);
  static const Color mutedSlate = Color(0xFF635F57);
  static const Color hairlineBorder = Color(0xFFE4DDD0);

  // Single primary brand accent (Event Emerald)
  static const Color emerald = Color(0xFF1F9D6B);
  static const Color emeraldDark = Color(0xFF157650);
  static const Color emeraldTint = Color(0xFFE7F6EF);

  // Semantic status colors
  static const Color coral = Color(0xFFD94F3D);
  static const Color coralTint = Color(0xFFFCECE9);

  static const Color amber = Color(0xFFC97A16);
  static const Color amberTint = Color(0xFFFDF3E3);

  static const Color slateTint = Color(0xFFECEAE4);
}

abstract final class EfSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract final class EfRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

abstract final class EfShadows {
  static List<BoxShadow> get softCard => [
        BoxShadow(
          color: EfColors.deepInk.withValues(alpha: 0.05),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
}

abstract final class EfTextStyles {
  static TextStyle display(double size,
      {FontWeight weight = FontWeight.w700, Color color = EfColors.deepInk}) {
    return GoogleFonts.outfit(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: -0.02 * size,
      color: color,
      height: 1.15,
    );
  }

  static TextStyle body(double size,
      {FontWeight weight = FontWeight.w400, Color color = EfColors.deepInk}) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.45,
    );
  }

  static TextStyle mono(double size,
      {FontWeight weight = FontWeight.w600, Color color = EfColors.deepInk}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.3,
    );
  }
}
