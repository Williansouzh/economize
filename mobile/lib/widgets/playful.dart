import 'package:flutter/material.dart';

/// Componentes no estilo "jogo" (splash, apresentação e configuração guiada).

/// Botão grande com "degrau" embaixo que afunda ao tocar.
class ChunkyButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color? textColor;
  final bool busy;
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF00A86B),
    this.textColor,
    this.busy = false,
  });

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;
  static const _depth = 5.0;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final base = enabled ? widget.color : Colors.grey.shade400;
    final edge = Color.lerp(base, Colors.black, .25)!;
    final fg = widget.textColor ?? (base.computeLuminance() > .6 ? const Color(0xFF1A1F1D) : Colors.white);
    final pressed = _down && enabled;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: () => setState(() => _down = false),
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        height: 56,
        margin: EdgeInsets.only(top: pressed ? _depth : 0),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [if (!pressed) BoxShadow(color: edge, offset: const Offset(0, _depth))],
        ),
        alignment: Alignment.center,
        child: widget.busy
            ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
            : Text(widget.label.toUpperCase(),
                style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: .8)),
      ),
    );
  }
}

/// O cofrinho do Economizze, pulando devagar.
class Mascot extends StatefulWidget {
  final double size;
  final bool bounce;
  const Mascot({super.key, this.size = 160, this.bounce = true});
  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.bounce) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -10 * Curves.easeInOut.transform(_c.value)),
          child: child,
        ),
        child: Image.asset('assets/mascot.png', width: widget.size, height: widget.size),
      );
}

/// O cofrinho dentro de um círculo verde, para telas de fundo claro.
class MascotAvatar extends StatelessWidget {
  final double size;
  final bool bounce;
  const MascotAvatar({super.key, this.size = 72, this.bounce = false});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF00C27C), Color(0xFF007A4D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Mascot(size: size, bounce: bounce),
      );
}

/// Balão de fala branco. A "pontinha" fica embaixo (mascote abaixo) ou à esquerda (mascote ao lado).
class SpeechBubble extends StatelessWidget {
  final Widget child;
  final bool tailLeft;
  const SpeechBubble({super.key, required this.child, this.tailLeft = false});

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      width: tailLeft ? null : double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE3EAE7), width: 2),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: DefaultTextStyle.merge(style: const TextStyle(color: Color(0xFF1A1F1D)), child: child),
    );
    final tail = CustomPaint(size: const Size(28, 14), painter: _TailPainter());
    if (!tailLeft) return Column(mainAxisSize: MainAxisSize.min, children: [bubble, tail]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 22), child: RotatedBox(quarterTurns: 1, child: tail)),
      Expanded(child: bubble),
    ]);
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    // Contorno só nos lados, para emendar com a borda do balão.
    final border = Paint()
      ..color = const Color(0xFFE3EAE7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width / 2, size.height), border);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width / 2, size.height), border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Barra de progresso grossa e arredondada (topo da configuração guiada).
class ChunkyProgress extends StatelessWidget {
  final double value;
  const ChunkyProgress({super.key, required this.value});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: value),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => LinearProgressIndicator(
            value: v,
            minHeight: 14,
            color: const Color(0xFF00C27C),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      );
}
