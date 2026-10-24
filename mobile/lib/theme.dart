import 'package:flutter/material.dart';

// Identidade visual: brand/README.md. Ícones e logos são gerados por brand/gerar.py.
const tinta = Color(0xFF0B2B2E); // texto forte, fundo do ícone e do tema escuro
const mar = Color(0xFF0C7A68);   // principal no tema claro (botões e links: 5,25:1 com branco)
const lima = Color(0xFFC5F04A);  // destaque: moeda, "zz", ação principal. Nunca texto sobre fundo claro.
const nevoa = Color(0xFFF2F6F4); // fundo do tema claro

const brandColor = mar;
const brandDark = tinta;

/// Fundo dos cartões e telas de destaque (saldo, login, apresentação).
const brandGradient = LinearGradient(colors: [mar, tinta], begin: Alignment.topLeft, end: Alignment.bottomRight);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  // Claro: mar como principal e lima nos destaques (indicador da barra, chips).
  // Escuro: a lima vira a principal, com texto tinta (11:1).
  final cs = ColorScheme.fromSeed(seedColor: mar, brightness: brightness).copyWith(
    primary: dark ? lima : mar,
    onPrimary: dark ? tinta : Colors.white,
    primaryContainer: dark ? const Color(0xFF24473B) : const Color(0xFFE2F7AE),
    onPrimaryContainer: dark ? const Color(0xFFE6F9B8) : tinta,
    secondary: dark ? const Color(0xFF7FD3C2) : mar,
    tertiary: lima,
    onTertiary: tinta,
  );
  final background = dark ? const Color(0xFF081E21) : nevoa;
  final surface = dark ? const Color(0xFF11302F) : Colors.white;
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
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
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
    // O "+" é a ação principal do app: a moeda lima da marca, nos dois temas.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: lima,
      foregroundColor: tinta,
      extendedTextStyle: const TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
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
