/// 应用主题：构建深色 `ThemeData`，将所有组件默认样式集中配置。
///
/// 对照 `docs/ui-spec.md` §二（设计令牌）与 §3.4（表单组件）。组件默认就
/// 符合规格，页面内不再逐处硬编码样式（版本差异用 `styleFrom` 局部覆盖）。
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// 构建应用深色主题（本应用为深色专用）。
ThemeData buildDarkTheme() {
  const colorScheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.textOnDark,
    secondary: AppColors.textAccent,
    onSecondary: AppColors.bgApp,
    tertiary: AppColors.success,
    onTertiary: AppColors.bgApp,
    error: AppColors.error,
    onError: AppColors.textOnDark,
    surface: AppColors.bgSurface,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSemantic,
    outline: AppColors.border,
  );

  const baseTextTheme = TextTheme(
    bodyMedium: TextStyle(fontSize: AppFontSizes.body),
    bodySmall: TextStyle(fontSize: AppFontSizes.small),
    labelMedium: TextStyle(fontSize: AppFontSizes.body),
    labelLarge: TextStyle(fontSize: AppFontSizes.body),
    titleMedium: TextStyle(fontSize: AppFontSizes.body),
    titleSmall: TextStyle(fontSize: AppFontSizes.small),
  );

  final textTheme = baseTextTheme.apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: AppColors.bgApp,
    canvasColor: AppColors.bgApp,
    textTheme: textTheme,
    dividerColor: AppColors.border,
    splashFactory: InkRipple.splashFactory,
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: AppColors.textSemantic, size: 18),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border.all(color: AppColors.borderStrong),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      textStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: AppFontSizes.small,
        fontFamily: AppFonts.body,
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
    inputDecorationTheme: _inputDecorationTheme(),
    filledButtonTheme: _filledButtonTheme(),
    outlinedButtonTheme: _outlinedButtonTheme(),
    textButtonTheme: _textButtonTheme(),
    dialogTheme: _dialogTheme(),
    tabBarTheme: _tabBarTheme(),
    dataTableTheme: _dataTableTheme(),
    switchTheme: _switchTheme(),
    segmentedButtonTheme: _segmentedButtonTheme(),
    checkboxTheme: _checkboxTheme(),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.bgSurface,
      contentTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: AppFontSizes.body,
        fontFamily: AppFonts.body,
      ),
      actionTextColor: AppColors.textAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.bgSurface,
      textStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: AppFontSizes.body,
        fontFamily: AppFonts.body,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
    ),
  );
}

InputDecorationTheme _inputDecorationTheme() {
  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: color, width: width),
  );

  return InputDecorationTheme(
    filled: true,
    fillColor: AppColors.bgSurface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s2,
      vertical: AppSpacing.s1,
    ),
    hintStyle: const TextStyle(
      color: AppColors.textSemantic,
      fontSize: AppFontSizes.body,
    ),
    labelStyle: const TextStyle(
      color: AppColors.textSemantic,
      fontSize: AppFontSizes.body,
    ),
    helperStyle: const TextStyle(
      color: AppColors.textSemantic,
      fontSize: AppFontSizes.caption,
    ),
    errorStyle: const TextStyle(
      color: AppColors.error,
      fontSize: AppFontSizes.caption,
    ),
    border: border(AppColors.border, 1),
    enabledBorder: border(AppColors.border, 1),
    focusedBorder: border(AppColors.focus, 2),
    errorBorder: border(AppColors.error, 2),
    focusedErrorBorder: border(AppColors.error, 2),
    disabledBorder: border(AppColors.border, 1),
  );
}

FilledButtonThemeData _filledButtonTheme() {
  return FilledButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.bgSurface.withValues(alpha: 0.4);
        }
        if (states.contains(WidgetState.hovered)) {
          return AppColors.accentHover;
        }
        return AppColors.accentStrong;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.textDisabled;
        }
        return AppColors.textOnDark;
      }),
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontSize: AppFontSizes.body, fontWeight: FontWeight.w500),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s1,
        ),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(
        Size(72, AppDims.fieldHeight),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      side: const WidgetStatePropertyAll<BorderSide>(BorderSide.none),
    ),
  );
}

OutlinedButtonThemeData _outlinedButtonTheme() {
  return OutlinedButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.textDisabled;
        }
        return AppColors.textSemantic;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.hovered)) {
          return AppColors.bgHover;
        }
        return AppColors.bgSurface;
      }),
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontSize: AppFontSizes.body),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s1,
        ),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 30)),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      side: WidgetStatePropertyAll<BorderSide>(
        BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
      ),
    ),
  );
}

TextButtonThemeData _textButtonTheme() {
  return TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.textDisabled;
        }
        return AppColors.textAccent;
      }),
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontSize: AppFontSizes.body),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s1,
        ),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 30)),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
  );
}

DialogThemeData _dialogTheme() {
  return DialogThemeData(
    backgroundColor: AppColors.bgSurface,
    surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: const BorderSide(color: AppColors.borderStrong),
    ),
    titleTextStyle: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: AppFontSizes.h3,
      fontWeight: FontWeight.w600,
      fontFamily: AppFonts.body,
    ),
    contentTextStyle: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: AppFontSizes.body,
      fontFamily: AppFonts.body,
    ),
  );
}

TabBarThemeData _tabBarTheme() {
  return TabBarThemeData(
    labelColor: AppColors.textPrimary,
    unselectedLabelColor: AppColors.textSemantic,
    indicatorColor: AppColors.accent,
    indicatorSize: TabBarIndicatorSize.tab,
    dividerColor: AppColors.border,
    labelStyle: const TextStyle(
      fontSize: AppFontSizes.body,
      fontFamily: AppFonts.body,
    ),
    unselectedLabelStyle: const TextStyle(
      fontSize: AppFontSizes.body,
      fontFamily: AppFonts.body,
    ),
    overlayColor: WidgetStatePropertyAll<Color>(AppColors.bgHover),
  );
}

DataTableThemeData _dataTableTheme() {
  return DataTableThemeData(
    headingRowColor: WidgetStatePropertyAll<Color>(AppColors.bgSurface),
    headingTextStyle: const TextStyle(
      color: AppColors.textSemantic,
      fontSize: AppFontSizes.small,
      fontWeight: FontWeight.w600,
      fontFamily: AppFonts.body,
    ),
    dataTextStyle: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: AppFontSizes.body,
      fontFamily: AppFonts.body,
    ),
    dataRowColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.hovered)) {
        return AppColors.bgHover;
      }
      return Colors.transparent;
    }),
    dividerThickness: 1,
    horizontalMargin: AppSpacing.s2,
    columnSpacing: AppSpacing.s3,
  );
}

SwitchThemeData _switchTheme() {
  return SwitchThemeData(
    trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.selected)) {
        return AppColors.accent;
      }
      return AppColors.bgSurface;
    }),
    thumbColor: WidgetStatePropertyAll<Color>(AppColors.textOnDark),
    trackOutlineColor: WidgetStatePropertyAll<Color>(AppColors.border),
  );
}

SegmentedButtonThemeData _segmentedButtonTheme() {
  return SegmentedButtonThemeData(
    style: ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.accentStrong;
        }
        return AppColors.bgSurface;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.textOnDark;
        }
        return AppColors.textSemantic;
      }),
      textStyle: const WidgetStatePropertyAll<TextStyle>(
        TextStyle(fontSize: AppFontSizes.body),
      ),
      side: const WidgetStatePropertyAll<BorderSide>(
        BorderSide(color: AppColors.border),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(
          horizontal: AppSpacing.s2,
          vertical: AppSpacing.s1,
        ),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
  );
}

CheckboxThemeData _checkboxTheme() {
  return CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      if (states.contains(WidgetState.selected)) {
        return AppColors.accent;
      }
      return Colors.transparent;
    }),
    checkColor: const WidgetStatePropertyAll<Color>(AppColors.textOnDark),
    side: const BorderSide(color: AppColors.border),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
  );
}
