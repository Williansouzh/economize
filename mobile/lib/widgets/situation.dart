import 'package:flutter/material.dart';

import '../utils/format.dart';

/// Cor, ícone e rótulo de cada situação da análise (RN-46).
({Color color, IconData icon, String label}) situationStyle(String status) => switch (status) {
      'otimo' => (color: incomeColor, icon: Icons.rocket_launch_rounded, label: 'Ótimo'),
      'bom' => (color: incomeColor, icon: Icons.thumb_up_alt_rounded, label: 'No azul'),
      'atencao' => (color: warningColor, icon: Icons.error_outline_rounded, label: 'Atenção'),
      'critico' => (color: expenseColor, icon: Icons.trending_down_rounded, label: 'No vermelho'),
      'acima' => (color: incomeColor, icon: Icons.trending_up_rounded, label: 'Acima da média'),
      'na_media' => (color: const Color(0xFF3B82F6), icon: Icons.balance_rounded, label: 'Na média'),
      'abaixo' => (color: warningColor, icon: Icons.south_east_rounded, label: 'Abaixo da média'),
      _ => (color: Colors.blueGrey, icon: Icons.hourglass_empty_rounded, label: 'Sem dados'),
    };

Color toneColor(String tone) => switch (tone) {
      'good' => incomeColor,
      'warn' => warningColor,
      'bad' => expenseColor,
      _ => const Color(0xFF3B82F6),
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
