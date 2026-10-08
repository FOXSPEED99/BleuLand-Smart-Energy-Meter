import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: C.brand,
    onPrimary: C.onBrand,
    secondary: C.brand,
    onSecondary: C.onBrand,
    surface: C.surface,
    onSurface: C.text,
    surfaceContainerHighest: C.surface2,
    outline: C.outline,
    error: C.critical,
    onError: Colors.white,
  );

  const base = TextTheme(
    // hero figure (live watts): one per screen
    displayLarge: TextStyle(fontSize: 56, height: 1.0, fontWeight: FontWeight.w600, letterSpacing: -1.5),
    displaySmall: TextStyle(fontSize: 34, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -0.8),
    headlineSmall: TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.3),
    titleLarge: TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontSize: 16, height: 1.3, fontWeight: FontWeight.w600),
    titleSmall: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontSize: 16, height: 1.45, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.3),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.4),
  );
  final text = base.apply(fontFamily: 'Poppins', bodyColor: C.text, displayColor: C.text);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    fontFamily: 'Poppins',
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: C.bg,
      ),
    ),
    cardTheme: const CardThemeData(
      color: C.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(R.lg))),
    ),
    dividerTheme: const DividerThemeData(color: C.outline, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.brand,
        foregroundColor: C.onBrand,
        disabledBackgroundColor: C.surface2,
        minimumSize: const Size.fromHeight(54),
        textStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(R.md))),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        side: const BorderSide(color: C.outline),
        minimumSize: const Size.fromHeight(54),
        textStyle: text.labelLarge,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(R.md))),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.brand, textStyle: text.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: S.lg, vertical: S.lg),
      hintStyle: text.bodyLarge?.copyWith(color: C.text3),
      labelStyle: text.bodyMedium?.copyWith(color: C.text2),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(R.md)),
        borderSide: BorderSide(color: C.outline),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(R.md)),
        borderSide: BorderSide(color: C.outline),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(R.md)),
        borderSide: BorderSide(color: C.brand, width: 1.5),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(R.md)),
        borderSide: BorderSide(color: C.critical),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: C.brand.withValues(alpha: 0.14),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall?.copyWith(color: s.contains(WidgetState.selected) ? C.text : C.text3),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.brand : C.text3, size: 24),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? C.surface2 : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? C.text : C.text2,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: C.outline)),
        textStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.surface2,
      contentTextStyle: text.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(R.md))),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: C.outline,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.onBrand : C.text2),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.brand : C.surface2),
      trackOutlineColor: const WidgetStatePropertyAll(C.outline),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: C.text2,
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodySmall?.copyWith(color: C.text2),
      contentPadding: const EdgeInsets.symmetric(horizontal: S.lg),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.brand),
  );
}
