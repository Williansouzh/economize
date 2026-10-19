import 'package:flutter/material.dart';

const brandColor = Color(0xFF00A86B);
const brandDark = Color(0xFF007A4D);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  // O fromSeed sozinho gera um verde acinzentado; fixa o verde da marca (no claro, um tom
  // um pouco mais escuro para o texto branco e os links terem contraste de 4,5:1).
  final cs = ColorScheme.fromSeed(seedColor: brandColor, brightness: brightness).copyWith(
    primary: dark ? const Color(0xFF2FD08F) : const Color(0xFF00875A),
    onPrimary: dark ? const Color(0xFF00391F) : Colors.white,
    primaryContainer: dark ? const Color(0xFF0B4D33) : const Color(0xFFCDF3E1),
    onPrimaryContainer: dark ? const Color(0xFFB9F5D8) : const Color(0xFF00422A),
  );
  final background = dark ? const Color(0xFF101413) : const Color(0xFFF3F6F5);
  final radius = BorderRadius.circular(16);

  final theme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Nunito',
    colorScheme: cs,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Nunito', fontSize: 24, fontWeight: FontWeight.w900, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: dark ? const Color(0xFF1A201E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1A201E) : Colors.white,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      extendedTextStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1A201E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.primaryContainer,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          )),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
  // A Nunito fica fina nos pesos padrão do Material; títulos e textos sobem um degrau.
  final t = theme.textTheme;
  return theme.copyWith(
    textTheme: t.copyWith(
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: t.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      bodySmall: t.bodySmall?.copyWith(fontWeight: FontWeight.w500),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
