import 'dart:math';

import 'package:flutter/material.dart';

import '../data/tips.dart';
import '../theme.dart';
import '../widgets/playful.dart';

/// Abertura do app: o cofrinho dá uma dica de finanças enquanto o app carrega.
/// O fundo verde continua a splash nativa do Android, sem piscar branco.
class SplashScreen extends StatefulWidget {
  /// Tempo mínimo na tela: dá para ler a dica, e os dados do Início já vêm carregando por trás.
  static const minDuration = Duration(milliseconds: 1600);

  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  final _tip = financeTips[Random().nextInt(financeTips.length)];
  late final _progress = AnimationController(vsync: this, duration: SplashScreen.minDuration)..forward();

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00C27C), brandDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(children: [
              const Spacer(flex: 2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SpeechBubble(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.lightbulb, color: Color(0xFFF5A524), size: 20),
                      SizedBox(width: 6),
                      Text('DICA DO DIA',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.2, color: brandDark)),
                    ]),
                    const SizedBox(height: 8),
                    Text(_tip, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4)),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
              const Mascot(size: 170),
              const Spacer(flex: 3),
              const Text('Economizze',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -.5)),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (_, _) => LinearProgressIndicator(
                      value: Curves.easeInOut.transform(_progress.value),
                      minHeight: 10,
                      color: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: .25),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
