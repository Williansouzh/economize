import 'dart:math';

import 'package:flutter/material.dart';

import '../data/tips.dart';
import '../theme.dart';
import '../widgets/coin_mark.dart';
import '../widgets/playful.dart';

/// Abertura do app: a moeda da marca cai girando, os dois "z" se desenham e o segundo sobe o
/// degrau (o dinheiro que sobra e sobe), um brilho passa, o nome aparece e uma dica fica embaixo.
/// O fundo é o mesmo tinta da splash nativa, então a troca não pisca.
class SplashScreen extends StatefulWidget {
  /// Tempo mínimo na tela: a animação de entrada termina, e os dados do Início já vêm carregando por trás.
  static const minDuration = Duration(milliseconds: 1800);

  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  final _tip = financeTips[Random().nextInt(financeTips.length)];
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Reduzir movimento" ligado no sistema: mostra a marca pronta, sem a animação de entrada.
    if (_intro.isDismissed) {
      MediaQuery.maybeDisableAnimationsOf(context) == true ? _intro.value = 1 : _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// Trecho da entrada (de 0 a 1) entre [start] e [end], com a curva dada.
  Animation<double> _step(double start, double end, [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: _intro, curve: Interval(start, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final drop = _step(0, .38, Curves.bounceOut);
    final spin = _step(0, .32, Curves.easeOut);
    final draw = _step(.30, .72, Curves.easeInOut);
    final rise = _step(.55, .80, Curves.elasticOut);
    final shine = _step(.74, .98, Curves.easeInOut);
    final name = _step(.62, .90);
    final footer = _step(.75, 1);
    const coin = 150.0;

    return Scaffold(
      backgroundColor: tinta,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
          child: Column(children: [
            const Spacer(flex: 5),
            AnimatedBuilder(
              animation: Listenable.merge([_intro, _loop]),
              builder: (_, _) {
                // Depois da entrada, flutua de leve; a sombra no chão acompanha.
                final float = _intro.isCompleted ? (sin(_loop.value * 2 * pi) * .5 + .5) : 0.0;
                return Column(children: [
                  Transform.translate(
                    offset: Offset(0, -220 * (1 - drop.value) - 8 * float),
                    // Gira como moeda jogada: a largura vai a zero e volta.
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..scaleByDouble(cos(spin.value * 2 * pi).abs().clamp(.08, 1), 1, 1, 1),
                      child: Stack(alignment: Alignment.center, children: [
                        CoinMark(size: coin, draw: draw.value, rise: rise.value),
                        CoinShine(t: shine.value, size: coin),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: (90 - 18 * float) * drop.value,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .22 - .06 * float),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 26),
            _FadeUp(
              animation: name,
              child: const Wordmark(size: 38),
            ),
            const Spacer(flex: 4),
            _FadeUp(
              animation: footer,
              child: Column(children: [
                _BouncingDots(_loop),
                const SizedBox(height: 28),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    _tip,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .9),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Aparece subindo um pouco.
class _FadeUp extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;
  const _FadeUp({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .25), end: Offset.zero).animate(animation),
          child: child,
        ),
      );
}

/// Três bolinhas pulando uma depois da outra: "carregando" sem barra de progresso.
class _BouncingDots extends StatelessWidget {
  final Animation<double> loop;
  const _BouncingDots(this.loop);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: loop,
        builder: (_, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Builder(builder: (_) {
                // Cada bolinha pula num terço da volta, com atraso em relação à anterior.
                final t = (loop.value - i * .15) % 1;
                final up = t < .35 ? sin(t / .35 * pi) : 0.0;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  width: 10,
                  height: 10,
                  transform: Matrix4.translationValues(0, -8 * up, 0),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .55 + .45 * up),
                    shape: BoxShape.circle,
                  ),
                );
              }),
          ],
        ),
      );
}
