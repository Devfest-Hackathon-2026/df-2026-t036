import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// EWOCURUの配色を一元管理し、独自描画の装飾でも同じ色を使う。
abstract final class AppColors {
  static const main = Color(0xFFC7EDFF);
  // Keep each fill unchanged and derive a slightly darker matching border.
  static Color borderFor(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl.withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0)).toColor();
  }

  static final ownIdea = HSLColor.fromColor(main).withHue(140).toColor();
  static final drawnIdea = HSLColor.fromColor(main).withHue(48).toColor();
  static final accentGreen = borderFor(ownIdea);
  static final accentYellow = borderFor(drawnIdea);
  // Stable tag colors derived from the shared brand palette.
  static final tagBackgrounds = <Color>[
    main,
    HSLColor.fromColor(main).withHue(145).toColor(),
    HSLColor.fromColor(main).withHue(38).toColor(),
    HSLColor.fromColor(main).withHue(275).toColor(),
  ];
  static const sub = Color(0xFF173C70);
  static const background = Color(0xFFF8FBFD);
  static const surface = Color(0xFFFFFFFF);
  static const text = sub;
  // 補助色は基本パレットから派生させ、画面ごとの色追加を防ぐ。
  static const muted = Color(0xFF66788A);
  static const outline = Color(0xFF9EDDFF);
  static const shadow = Color(0x14173C70);
}

/// 色・書体・標準部品の形状を全画面へ適用する共通テーマ。
abstract final class AppTheme {
  static const cardRadius = 24.0;
  static const controlRadius = 14.0;

  static ThemeData get light {
    // エラーなどの意味色はMaterial標準を基にし、ブランド色を明示する。
    final colors = ColorScheme.fromSeed(seedColor: AppColors.sub).copyWith(
      primary: AppColors.sub,
      onPrimary: AppColors.background,
      primaryContainer: AppColors.main,
      onPrimaryContainer: AppColors.sub,
      secondary: AppColors.sub,
      onSecondary: AppColors.background,
      secondaryContainer: AppColors.main,
      onSecondaryContainer: AppColors.sub,
      tertiary: AppColors.sub,
      onTertiary: AppColors.background,
      tertiaryContainer: AppColors.main,
      onTertiaryContainer: AppColors.sub,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surface,
      surfaceContainerHighest: AppColors.main,
      surfaceTint: AppColors.sub,
      outline: AppColors.outline,
      outlineVariant: AppColors.outline,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    // 現在のgoogle_fontsとFlutterのTextTheme型の差を避けて書体を適用する。
    final family = GoogleFonts.mPlusRounded1c().fontFamily;
    final rounded = base.textTheme.apply(fontFamily: family);
    final textTheme = rounded.copyWith(
      headlineSmall: rounded.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      titleLarge: rounded.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      titleMedium: rounded.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.5,
      ),
      bodyLarge: rounded.bodyLarge?.copyWith(fontSize: 16, height: 1.7),
      bodyMedium: rounded.bodyMedium?.copyWith(fontSize: 14, height: 1.65),
      bodySmall: rounded.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.5,
        color: AppColors.muted,
      ),
      labelLarge: rounded.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.sub,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(bottom: BorderSide(color: AppColors.outline)),
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.sub,
          letterSpacing: 1.6,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: AppColors.outline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 80,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: const WidgetStatePropertyAll(
          IconThemeData(size: 24, color: AppColors.sub),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            fontSize: 12,
            color: states.contains(WidgetState.selected)
                ? AppColors.sub
                : AppColors.muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.main,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.sub,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.background,
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
