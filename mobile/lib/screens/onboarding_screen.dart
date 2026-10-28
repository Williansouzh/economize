import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/playful.dart';

/// Apresentação do app na primeira vez que ele é aberto, antes do login: 3 páginas com o Cofrinho
/// em todas, nos fundos da marca (tinta, mar e lima). O fundo muda junto com o arraste.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  final String title, text;
  final MascotPose pose;
  final Color background, foreground;
  const _Page(this.title, this.text, this.pose, this.background, this.foreground);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  double _position = 0;

  static const _pages = [
    _Page(
      'Oi! Eu sou o Cofrinho 👋',
      'Vou te ajudar a entender para onde vai o seu dinheiro e a guardar um pouco mais todo mês.',
      MascotPose.waving,
      tinta,
      Colors.white,
    ),
    _Page(
      'Anote em segundos',
      'Lance pelo app em 3 toques ou mande "gastei 30 no almoço", um áudio ou o print do Pix no WhatsApp.',
      MascotPose.phone,
      mar,
      Colors.white,
    ),
    _Page(
      'Uma IA do seu lado',
      'Uma nota do mês, dicas do que dá para economizar e aviso antes de você passar do limite.',
      MascotPose.thinking,
      lima,
      tinta,
    ),
  ];

  int get _page => _position.round();
  bool get _last => _page == _pages.length - 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _position = _controller.page ?? 0));
  }

  void _next() {
    if (_last) {
      context.read<AppState>().completeOnboarding();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cor de fundo e do texto interpoladas entre as páginas durante o arraste.
    final i = _position.floor().clamp(0, _pages.length - 1);
    final j = (i + 1).clamp(0, _pages.length - 1);
    final t = (_position - i).clamp(0.0, 1.0);
    final bg = Color.lerp(_pages[i].background, _pages[j].background, t)!;
    final fg = Color.lerp(_pages[i].foreground, _pages[j].foreground, t)!;
    final onLima = _pages[_page].background == lima;
    final buttonColor = onLima ? tinta : lima;
    final buttonText = onLima ? Colors.white : tinta;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: onLima ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: _last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: fg),
                  onPressed: _last ? null : () => context.read<AppState>().completeOnboarding(),
                  child: const Text('Pular'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                children: [
                  for (final p in _pages)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        // O Cofrinho é branco: fica num círculo escuro para não sumir no fundo lima.
                        Container(
                          width: 240,
                          height: 240,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: p.background == tinta ? mar.withValues(alpha: .35) : tinta.withValues(alpha: p.background == lima ? 1 : .35),
                          ),
                          child: Mascot(size: 220, pose: p.pose),
                        ),
                        const SizedBox(height: 32),
                        Text(p.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, height: 1.2, color: p.foreground)),
                        const SizedBox(height: 12),
                        Text(p.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 17, height: 1.5, fontWeight: FontWeight.w600, color: p.foreground.withValues(alpha: .85))),
                      ]),
                    ),
                ],
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 0; k < _pages.length; k++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: k == _page ? 26 : 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: k == _page ? fg : fg.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  ChunkyButton(
                    label: _last ? 'Começar' : 'Continuar',
                    onPressed: _next,
                    color: buttonColor,
                    textColor: buttonText,
                  ),
                  SizedBox(
                    height: 48,
                    child: _last
                        ? TextButton(
                            style: TextButton.styleFrom(foregroundColor: fg),
                            onPressed: () => context.read<AppState>().completeOnboarding(signIn: true),
                            child: const Text('Já tenho conta'),
                          )
                        : null,
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
