import 'package:animations/animations.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

// Identidade visual: brand/README.md. Ícones e logos são gerados por brand/gerar.py.
// Direção de arte (out/2026): "dinheiro em ordem, sem peso". A marca aparece em poucos lugares e
// com força (saldo, Lançar, seleção); o resto é calmo. Escalas geradas em OKLCH com o tom fixo:
// a cor da marca entra no seu degrau exato (mar = 600, lima = 200, tinta = 900).
const tinta = Color(0xFF0B2B2E); // texto forte, fundo do ícone e do tema escuro
const mar = Color(0xFF0C7A68);   // principal no tema claro (botões e links: 5,25:1 com branco)
const lima = Color(0xFFC5F04A);  // destaque: moeda, "zz", ação principal. Nunca texto sobre fundo claro.
const nevoa = Color(0xFFF2F6F4); // fundo do tema claro

const brandColor = mar;
const brandDark = tinta;

// Degraus usados das escalas.
const mar100 = Color(0xFFDAF4EC);
const mar300 = Color(0xFF91D4C3);
const tinta100 = Color(0xFFE3F0F1);
const tinta200 = Color(0xFFCBDFE1);
const tinta600 = Color(0xFF497175);
const tinta700 = Color(0xFF32575B);
const lima100 = Color(0xFFE5F4CA);

/// Fundo do cartão do saldo, do login e da apresentação. Só nesses lugares (nunca em IA ou alertas).
const brandGradient = LinearGradient(colors: [mar, tinta], begin: Alignment.topLeft, end: Alignment.bottomRight);

/// Sombra única do app: só no saldo e no botão Lançar, e só no tema claro.
const brandShadow = [BoxShadow(color: Color(0x3D0B2B2E), blurRadius: 16, offset: Offset(0, 6))];

/// Espaçamentos (base 4). Entre seções, 32; margem lateral, 16; padding de cartão, 20.
abstract final class Space {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 20.0, xxl = 24.0, section = 32.0, huge = 40.0;
}

/// Cores que dependem do tema e que o ColorScheme não tem: valores (receita/despesa), status e
/// profundidade do tema escuro. Uso: `context.colors.income`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color income, expense, warning, success, info;

  /// Selo de atenção (pendente, "atenção"): fundo e texto.
  final Color warningSoft, onWarningSoft;

  /// Cartão em destaque e borda dos cartões (no escuro a profundidade vem da cor, não da sombra).
  final Color raised, cardBorder;

  /// Linhas de grade dos gráficos.
  final Color grid;

  const AppColors({
    required this.income,
    required this.expense,
    required this.warning,
    required this.success,
    required this.info,
    required this.warningSoft,
    required this.onWarningSoft,
    required this.raised,
    required this.cardBorder,
    required this.grid,
  });

  // Claro: todos com pelo menos 4,5:1 sobre o branco.
  static const light = AppColors(
    income: Color(0xFF13864D),
    expense: Color(0xFFD24148),
    warning: Color(0xFFA96404),
    success: mar,
    info: Color(0xFF2E69B2),
    warningSoft: Color(0xFFFDF0D9),
    onWarningSoft: Color(0xFF7A4800),
    raised: Colors.white,
    cardBorder: Colors.transparent,
    grid: tinta100,
  );

  // Escuro: tons próprios, pelo menos 6:1 sobre a superfície #11302F.
  static const dark = AppColors(
    income: Color(0xFF5FD39A),
    expense: Color(0xFFFF8A8A),
    warning: Color(0xFFF2B53D),
    success: mar300,
    info: Color(0xFF7CB8FF),
    warningSoft: Color(0xFF3A3115),
    onWarningSoft: Color(0xFFF2B53D),
    raised: Color(0xFF163B39),
    cardBorder: Color(0xFF24473B),
    grid: Color(0x33A7BDBE),
  );

  /// Cor de status de um progresso de gasto: ok até 79%, atenção de 80% a 99%, estourou a partir de 100%.
  Color forProgress(double p) => p >= 1 ? expense : (p >= .8 ? warning : success);

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      income: l(income, other.income),
      expense: l(expense, other.expense),
      warning: l(warning, other.warning),
      success: l(success, other.success),
      info: l(info, other.info),
      warningSoft: l(warningSoft, other.warningSoft),
      onWarningSoft: l(onWarningSoft, other.onWarningSoft),
      raised: l(raised, other.raised),
      cardBorder: l(cardBorder, other.cardBorder),
      grid: l(grid, other.grid),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? (Theme.of(this).brightness == Brightness.dark ? AppColors.dark : AppColors.light);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Valores com dígitos de largura igual. A Nunito já desenha os números com a mesma largura
/// (600 unidades em todos os pesos), então colunas de valores alinham sem a feature "tnum".
const valueStyle = TextStyle(fontSize: 16, fontWeight: FontWeight.w800);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF081E21) : nevoa;
  final surface = dark ? const Color(0xFF11302F) : Colors.white;
  // Claro: mar como principal e lima nos destaques (indicador da barra, chips).
  // Escuro: a lima vira a principal, com texto tinta (11:1).
  final cs = ColorScheme.fromSeed(seedColor: mar, brightness: brightness).copyWith(
    primary: dark ? lima : mar,
    onPrimary: dark ? tinta : Colors.white,
    primaryContainer: dark ? const Color(0xFF24473B) : const Color(0xFFE2F7AE),
    onPrimaryContainer: dark ? const Color(0xFFE6F9B8) : tinta,
    secondary: dark ? mar300 : mar,
    tertiary: lima,
    onTertiary: tinta,
    surface: surface,
    onSurface: dark ? const Color(0xFFE8F2F1) : tinta,
    onSurfaceVariant: dark ? const Color(0xFFA7BDBE) : tinta600,
    outline: dark ? const Color(0xFF5E7F80) : const Color(0xFF86ADB1),
    outlineVariant: dark ? const Color(0xFF24473B) : tinta200,
    surfaceContainerLowest: dark ? const Color(0xFF0B2427) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF0E2A2C) : const Color(0xFFF7FAF9),
    surfaceContainer: dark ? const Color(0xFF11302F) : const Color(0xFFF1F8F9),
    surfaceContainerHigh: dark ? const Color(0xFF163B39) : const Color(0xFFEAF3F4),
    surfaceContainerHighest: dark ? const Color(0xFF1E3E41) : tinta100,
    error: dark ? const Color(0xFFFF8A8A) : const Color(0xFFD24148),
  );
  final colors = dark ? AppColors.dark : AppColors.light;
  final radius = BorderRadius.circular(16);
  const font = 'Nunito';

  final theme = ThemeData(
    useMaterial3: true,
    fontFamily: font,
    colorScheme: cs,
    extensions: [colors],
    scaffoldBackgroundColor: background,
    canvasColor: background,
    dividerTheme: DividerThemeData(color: cs.outlineVariant, space: 1, thickness: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: cs.onSurface,
      titleTextStyle: TextStyle(fontFamily: font, fontSize: 24, fontWeight: FontWeight.w900, color: cs.onSurface),
    ),
    // Três níveis: destaque (degradê), cartão (superfície) e lista sem cartão sobre o fundo.
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: dark ? BorderSide(color: colors.cardBorder) : BorderSide.none,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: cs.onSurfaceVariant,
      titleTextStyle: TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
      subtitleTextStyle: TextStyle(fontFamily: font, fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: cs.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    // Um só botão principal: 52 de altura, raio 16, 16/800, sem caixa alta, sempre na cor primária.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: cs.outlineVariant),
        textStyle: const TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    // Seleção única no app todo: fundo primaryContainer + check + texto forte, sem borda colorida.
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      showCheckmark: true,
      checkmarkColor: cs.onPrimaryContainer,
      selectedColor: cs.primaryContainer,
      backgroundColor: surface,
      side: WidgetStateBorderSide.resolveWith(
          (s) => s.contains(WidgetState.selected) ? BorderSide.none : BorderSide(color: cs.outlineVariant)),
      labelStyle: WidgetStateTextStyle.resolveWith((s) => TextStyle(
            fontFamily: font,
            fontSize: 14,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: s.contains(WidgetState.selected) ? cs.onPrimaryContainer : cs.onSurface,
          )),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: cs.primaryContainer,
        selectedForegroundColor: cs.onPrimaryContainer,
        side: BorderSide(color: cs.outlineVariant),
        textStyle: const TextStyle(fontFamily: font, fontWeight: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : cs.outline),
    ),
    // O "+" é a ação principal do app: a moeda lima da marca, nos dois temas.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: lima,
      foregroundColor: tinta,
      extendedTextStyle: const TextStyle(fontFamily: font, fontSize: 16, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.primaryContainer,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: font,
            fontSize: 12,
            color: cs.onSurface,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
          )),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: cs.outline,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    // Diálogo só para confirmação; criar e editar abrem folhas de baixo.
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(fontFamily: font, fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface),
      contentTextStyle: TextStyle(fontFamily: font, fontSize: 15, height: 1.45, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: tinta, borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontFamily: font, color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFE8F2F1) : tinta,
      contentTextStyle: TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600, color: dark ? tinta : Colors.white),
      actionTextColor: dark ? mar : lima,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary, linearTrackColor: cs.surfaceContainerHighest),
    // Push entre telas: eixo compartilhado horizontal (Material motion).
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: SharedAxisPageTransitionsBuilder(transitionType: SharedAxisTransitionType.horizontal),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: SharedAxisPageTransitionsBuilder(transitionType: SharedAxisTransitionType.horizontal),
      TargetPlatform.windows: SharedAxisPageTransitionsBuilder(transitionType: SharedAxisTransitionType.horizontal),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
  );
  // Escala de texto: corpo 15/500 (lido no ônibus, com uma mão), metadados 13/600, legenda mínima 12.
  final t = theme.textTheme;
  return theme.copyWith(
    textTheme: t.copyWith(
      displaySmall: t.displaySmall?.copyWith(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -.5),
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
      headlineSmall: t.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w900),
      titleLarge: t.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w800),
      titleMedium: t.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w800),
      titleSmall: t.titleSmall?.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      bodySmall: t.bodySmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      labelLarge: t.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
      labelMedium: t.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
      labelSmall: t.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .5),
    ),
  );
}
