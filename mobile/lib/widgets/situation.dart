import 'package:flutter/material.dart';

import '../theme.dart';

/// Cor, ícone e rótulo de cada situação da análise (RN-46). O ponto de partida não tem ranking
/// negativo: quem ganha menos que a maioria vê "Seu ponto de partida", não "abaixo da média".
({Color color, IconData icon, String label}) situationStyle(BuildContext context, String status) {
  final c = context.colors;
  return switch (status) {
    'otimo' => (color: c.success, icon: Icons.rocket_launch_rounded, label: 'Ótimo'),
    'bom' => (color: c.success, icon: Icons.thumb_up_alt_rounded, label: 'No azul'),
    'atencao' => (color: c.warning, icon: Icons.error_outline_rounded, label: 'Atenção'),
    'critico' => (color: c.expense, icon: Icons.trending_down_rounded, label: 'No vermelho'),
    'acima' => (color: c.success, icon: Icons.trending_up_rounded, label: 'Acima da maioria'),
    'na_media' => (color: c.info, icon: Icons.balance_rounded, label: 'No meio do caminho'),
    'abaixo' => (color: c.info, icon: Icons.flag_rounded, label: 'Ponto de partida'),
    _ => (color: Theme.of(context).colorScheme.onSurfaceVariant, icon: Icons.hourglass_empty_rounded, label: 'Sem dados'),
  };
}

Color toneColor(BuildContext context, String tone) => switch (tone) {
      'good' => context.colors.success,
      'warn' => context.colors.warning,
      'bad' => context.colors.expense,
      _ => context.colors.info,
    };

/// Ícones usados pela API nos pontos da análise.
IconData analysisIcon(String name) => switch (name) {
      'bar_chart' => Icons.bar_chart_rounded,
      'place' => Icons.place_outlined,
      'work' => Icons.work_outline,
      'shield' => Icons.shield_outlined,
      'show_chart' => Icons.show_chart,
      'storefront' => Icons.storefront_outlined,
      'pie_chart' => Icons.pie_chart_outline,
      'flag' => Icons.flag_outlined,
      'trending_up' => Icons.trending_up,
      'warning' => Icons.warning_amber_rounded,
      'event' => Icons.event_outlined,
      'speed' => Icons.speed,
      'receipt_long' => Icons.receipt_long_outlined,
      'person' => Icons.person_outline,
      'savings' => Icons.savings_outlined,
      _ => Icons.lightbulb_outline,
    };
