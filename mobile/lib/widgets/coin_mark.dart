import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Símbolo da marca desenhado em código (mesma geometria de brand/gerar.py, viewBox 100x100):
/// a moeda e o "zz", com o segundo z um degrau acima. Os parâmetros permitem animar:
/// [draw] desenha os traços do zz (0 a 1) e [rise] leva o segundo z do nível do primeiro até o degrau.
class CoinMark extends StatelessWidget {
  final double size, draw, rise;
  final Color coin, zz;
  const CoinMark({super.key, this.size = 120, this.draw = 1, this.rise = 1, this.coin = lima, this.zz = tinta});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Economizze',
        image: true,
        child: CustomPaint(size: Size.square(size), painter: _CoinPainter(draw, rise, coin, zz)),
      );
}

class _CoinPainter extends CustomPainter {
  final double draw, rise;
  final Color coin, zz;
  _CoinPainter(this.draw, this.rise, this.coin, this.zz);

  // brand/gerar.py: COIN_R=33, ZW=8 (+1 na versão cheia), Z_W=14, Z_H=20, Z_GAP=6, Z_RISE=8.
  static const _r = 33.0, _stroke = 9.0, _w = 14.0, _h = 20.0, _gap = 6.0, _riseMax = 8.0;

  Path _z(double x, double y) => Path()
    ..moveTo(x, y)
    ..lineTo(x + _w, y)
    ..lineTo(x, y + _h)
    ..lineTo(x + _w, y + _h);

  /// Primeiro trecho do caminho, do começo até [t] (0 a 1) do comprimento.
  Path _partial(Path p, double t) {
    final out = Path();
    for (final m in p.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * t.clamp(0, 1)), Offset.zero);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    // A moeda ocupa 66% do viewBox: aqui ela preenche o tamanho pedido.
    canvas.scale(s * 100 / (2 * _r));
    canvas.translate(-(50 - _r), -(50 - _r));
    canvas.drawCircle(const Offset(50, 50), _r, Paint()..color = coin);

    const x0 = 50 - (2 * _w + _gap) / 2;
    const yLow = 50 - _h / 2 + _riseMax / 2;
    final paint = Paint()
      ..color = zz
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Os dois z se desenham um depois do outro; o segundo começa no nível do primeiro e sobe.
    final first = (draw * 2).clamp(0.0, 1.0);
    final second = (draw * 2 - 1).clamp(0.0, 1.0);
    if (first > 0) canvas.drawPath(_partial(_z(x0, yLow), first), paint);
    if (second > 0) {
      canvas.drawPath(_partial(_z(x0 + _w + _gap, yLow - _riseMax * rise), second), paint);
    }
  }

  @override
  bool shouldRepaint(_CoinPainter old) =>
      old.draw != draw || old.rise != rise || old.coin != coin || old.zz != zz;
}

/// Brilho que passa uma vez pela moeda quando ela termina de se montar.
class CoinShine extends StatelessWidget {
  final double t, size;
  const CoinShine({super.key, required this.t, required this.size});

  @override
  Widget build(BuildContext context) {
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: Transform.translate(
            offset: Offset(lerpDouble(-size, size, t)!, 0),
            child: Transform.rotate(
              angle: .5,
              child: Container(
                width: size * .28,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: .55),
                    Colors.white.withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
