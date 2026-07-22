import 'package:flutter/material.dart';

/// Central place for the app's visual identity: colors, gradients and the
/// two ThemeData instances (light/dark). Keeping this separate from widgets
/// avoids scattering magic colors across screens.
class AppTheme {
  AppTheme._();

  static const seed = Color(0xFF0EA5A0); // teal-cyan, distinct from Material's default purple
  static const signalWeak = Color(0xFFEF4444);
  static const signalMid = Color(0xFFF59E0B);
  static const signalStrong = Color(0xFF22C55E);

  static const _fontFamily = null; // use platform default but with tuned weights below

  static ThemeData light = _build(Brightness.light);
  static ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: _textTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5)),
    );
  }

  static TextTheme _textTheme(ColorScheme scheme) {
    return const TextTheme().copyWith(
      headlineMedium: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      titleLarge: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: const TextStyle(fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
      bodySmall: TextStyle(color: scheme.onSurfaceVariant),
    );
  }

  /// Background gradient used behind hero-style screens.
  static LinearGradient heroGradient(ColorScheme scheme) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          scheme.primaryContainer.withValues(alpha: 0.55),
          scheme.surface,
        ],
      );

  /// Red -> amber -> green, matching the heatmap's quality color mapping.
  static const signalGradient = LinearGradient(
    colors: [signalWeak, signalMid, signalStrong],
  );

  static Color colorForQuality(double quality) {
    final hue = quality.clamp(0.0, 1.0) * 120.0;
    return HSVColor.fromAHSV(1.0, hue, 0.85, 0.95).toColor();
  }

  static const bestRssiDbm = -30;
  static const worstRssiDbm = -85;

  static double qualityForRssi(int rssiDbm) {
    return ((rssiDbm - worstRssiDbm) / (bestRssiDbm - worstRssiDbm)).clamp(0.0, 1.0);
  }
}
