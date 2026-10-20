import 'dart:math';

import 'package:flutter/material.dart';

import '../data/tips.dart';
import '../theme.dart';

/// Abertura do app: o cofrinho entra pulando, o nome aparece e uma dica curta fica embaixo.
/// O fundo é o mesmo verde da splash nativa do Android, então a troca não pisca.
class SplashScreen extends StatefulWidget {
  /// Tempo mínimo na tela: a animação de entrada termina, e os dados do Início já vêm carregando por trás.
  static const minDuration = Duration(milliseconds: 1400);

  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  final _tip = financeTips[Random().nextInt(financeTips.length)];
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
  late final _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

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
    final pop = _step(0, .6, Curves.elasticOut);
    final name = _step(.25, .65);
    final footer = _step(.45, .9);

    return Scaffold(
      backgroundColor: brandColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
          child: Column(children: [
            const Spacer(flex: 5),
            // Cofrinho: entra crescendo com um quique e depois flutua; a sombra no chão acompanha.
            ScaleTransition(
              scale: Tween(begin: .6, end: 1.0).animate(pop),
              child: AnimatedBuilder(
                animation: _loop,
                builder: (_, child) {
                  final lift = sin(_loop.value * 2 * pi) * .5 + .5;
                  return Column(children: [
                    Transform.translate(offset: Offset(0, -12 * lift), child: child),
                    const SizedBox(height: 6),
                    Container(
                      width: 96 - 22 * lift,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .12 - .05 * lift),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ]);
                },
                // A imagem tem uma folga transparente embaixo: corta para a sombra ficar rente aos pés.
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: .82,
                  child: Image.asset('assets/mascot.png', width: 190, height: 190),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _FadeUp(
              animation: name,
              child: const Text(
                'Economizze',
                style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -.8),
              ),
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
