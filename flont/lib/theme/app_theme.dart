import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// EOCURUの配色を一元管理し、独自描画の装飾でも同じ色を使う。
abstract final class AppColors {
  static const main = Color(0xFFC7EDFF);
  // 共通アクセント二色。枠線は既存のoutlineと彩度・明度をそろえる。
  static final accentGreen = HSLColor.fromColor(outline).withHue(140).toColor();
  static final accentYellow = HSLColor.fromColor(outline).withHue(48).toColor();
  // 背景には同じアクセントの色相と、メイン色の明るさを使用する。
  static final ownIdea = HSLColor.fromColor(
    main,
  ).withHue(HSLColor.fromColor(accentGreen).hue).toColor();
  static final drawnIdea = HSLColor.fromColor(
    main,
  ).withHue(HSLColor.fromColor(accentYellow).hue).toColor();
  // Stable tag colors derived from the shared brand palette.
  static final tagBackgrounds = <Color>[
    main,
    HSLColor.fromColor(main).withHue(145).toColor(),
    HSLColor.fromColor(main).withHue(38).toColor(),
    HSLColor.fromColor(main).withHue(275).toColor(),
  ];
  static const sub = Color(0xFF173C70);
  static const background = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF7FBFF);
  static const text = Color(0xFF000000);
  // 補助色は基本パレットから派生させ、画面ごとの色追加を防ぐ。
  static const muted = Color(0xFF4C617D);
  static const outline = Color(0xFFBDD2E4);
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
    final textTheme = base.textTheme.apply(fontFamily: family);
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.sub,
        foregroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: AppColors.background,
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
      navigationBarTheme: const NavigationBarThemeData(
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
