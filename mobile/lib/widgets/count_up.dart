import 'package:flutter/material.dart';

import '../utils/format.dart';

/// Valor em reais que "sobe" até o número ao aparecer e anima de um valor para o outro quando muda
/// (troca de mês, novo lançamento). Leitores de tela recebem só o valor final.
class CountUpMoney extends StatelessWidget {
  final double value;
  final TextStyle? style;
  final Duration duration;
  final String Function(double) format;
  const CountUpMoney(this.value,
      {super.key, this.style, this.duration = const Duration(milliseconds: 900), this.format = money});

  @override
  Widget build(BuildContext context) {
    // Com "reduzir movimento" ligado no sistema, mostra o número direto.
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) return Text(format(value), style: style);
    return Semantics(
      label: format(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(format(v), style: style),
      ),
    );
  }
}
