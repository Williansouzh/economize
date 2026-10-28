import 'package:flutter/material.dart';
import '../theme.dart';

/// Componentes no estilo "jogo" (splash, apresentação e configuração guiada).

/// Poses do Cofrinho (geradas por brand/gerar.py). Ele só aparece em momentos: fala uma frase e sai.
enum MascotPose {
  normal('assets/mascot.png'),
  waving('assets/mascot_acenando.png'), // apresentação
  thinking('assets/mascot_pensando.png'), // IA carregando
  celebrating('assets/mascot_comemorando.png'), // meta batida, primeiro lançamento
  sleeping('assets/mascot_dormindo.png'), // estados vazios
  phone('assets/mascot_celular.png'), // WhatsApp
  worried('assets/mascot_preocupado.png'); // orçamento estourado

  final String asset;
  const MascotPose(this.asset);
}

/// Botão grande com "degrau" embaixo que afunda ao tocar. Variante do botão principal só para a
/// apresentação e a configuração guiada; o resto do app usa o FilledButton do tema.
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
    this.color = mar,
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
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? widget.onPressed : null,
      child: GestureDetector(
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
            : Text(widget.label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
    ),
    );
  }
}

/// O cofrinho do Economizze, pulando devagar.
class Mascot extends StatefulWidget {
  final double size;
  final bool bounce;
  final MascotPose pose;
  const Mascot({super.key, this.size = 160, this.bounce = true, this.pose = MascotPose.normal});
  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Reduzir movimento" no sistema: o Cofrinho fica parado.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.bounce && !reduce && !_c.isAnimating) _c.repeat(reverse: true);
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Image.asset(widget.pose.asset,
              key: ValueKey(widget.pose), width: widget.size, height: widget.size, excludeFromSemantics: true),
        ),
      );
}

/// O cofrinho dentro de um círculo verde, para telas de fundo claro.
class MascotAvatar extends StatelessWidget {
  final double size;
  final bool bounce;
  final MascotPose pose;
  const MascotAvatar({super.key, this.size = 72, this.bounce = false, this.pose = MascotPose.normal});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: brandGradient),
        child: Mascot(size: size, bounce: bounce, pose: pose),
      );
}

/// Balão de fala branco. A "pontinha" fica embaixo (mascote abaixo) ou à esquerda (mascote ao lado).
class SpeechBubble extends StatelessWidget {
  final Widget child;
  final bool tailLeft;
  const SpeechBubble({super.key, required this.child, this.tailLeft = false});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF163B39) : Colors.white;
    final edge = dark ? const Color(0xFF24473B) : const Color(0xFFE3EAE7);
    final bubble = Container(
      width: tailLeft ? null : double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: edge, width: 2),
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: dark ? const Color(0xFFE8F2F1) : tinta), child: child),
    );
    final tail = CustomPaint(size: const Size(28, 14), painter: _TailPainter(fill, edge));
    if (!tailLeft) return Column(mainAxisSize: MainAxisSize.min, children: [bubble, tail]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 22), child: RotatedBox(quarterTurns: 1, child: tail)),
      Expanded(child: bubble),
    ]);
  }
}

class _TailPainter extends CustomPainter {
  final Color fill, edge;
  _TailPainter(this.fill, this.edge);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    // Contorno só nos lados, para emendar com a borda do balão.
    final border = Paint()
      ..color = edge
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width / 2, size.height), border);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width / 2, size.height), border);
  }

  @override
  bool shouldRepaint(covariant _TailPainter old) => old.fill != fill || old.edge != edge;
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
            minHeight: 10,
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
      );
}

/// O nome da marca escrito como no logo: "economizze" em Nunito Black, com o "zz" em destaque.
class Wordmark extends StatelessWidget {
  final double size;
  final Color color;
  final Color accent;
  const Wordmark({super.key, this.size = 34, this.color = Colors.white, this.accent = lima});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontFamily: 'Nunito', fontSize: size, fontWeight: FontWeight.w900, letterSpacing: -size * .01, color: color);
    return Semantics(
      label: 'Economizze',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(style: style, children: [
            const TextSpan(text: 'economi'),
            TextSpan(text: 'zz', style: TextStyle(color: accent)),
            const TextSpan(text: 'e'),
          ]),
        ),
      ),
    );
  }
}
