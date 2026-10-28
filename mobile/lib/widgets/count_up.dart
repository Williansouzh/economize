import 'package:flutter/material.dart';

import '../utils/format.dart';

/// Valor em reais que "sobe" até o número ao aparecer e anima de um valor para o outro quando muda.
/// Com [memory], lembra o último valor mostrado com essa chave: na volta, só anima se o valor mudou
/// desde a última visita (do antigo ao novo, 500 ms). Leitores de tela recebem só o valor final.
class CountUpMoney extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final Duration duration;
  final String Function(double) format;
  final String? memory;
  const CountUpMoney(this.value,
      {super.key, this.style, this.duration = const Duration(milliseconds: 900), this.format = money, this.memory});

  static final _last = <String, double>{};

  @override
  Widget build(BuildContext context) {
    // Com "reduzir movimento" ligado no sistema, mostra o número direto.
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return Text(format(value), style: style);
    final from = memory == null ? 0.0 : (_last[memory!] ?? 0.0);
    if (memory != null) _last[memory!] = value;
    if (from == value) return Text(format(value), style: style);
    return Semantics(
      label: format(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: from, end: value),
        duration: memory == null ? duration : const Duration(milliseconds: 500),
        curve: memory == null ? Curves.easeOutCubic : Curves.easeOutExpo,
        builder: (_, v, _) => Text(format(v), style: style),
      ),
    );
  }
}
