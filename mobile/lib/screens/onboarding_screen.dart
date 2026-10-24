import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/playful.dart';

/// Apresentação do app na primeira vez que ele é aberto, antes do login.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  final String title, text;
  final Widget art;
  const _Page(this.title, this.text, this.art);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static final _pages = [
    const _Page(
      'Oi! Eu sou o Cofrinho 👋',
      'Vou te ajudar a entender para onde vai o seu dinheiro e a guardar mais todo mês.',
      _Art(child: Mascot(size: 190)),
    ),
    const _Page(
      'Registre tudo em segundos',
      'Lance gastos e receitas pelo app ou mande uma mensagem, um áudio ou o print do comprovante no WhatsApp.',
      _Art(icon: Icons.chat_rounded, color: Color(0xFF25D366), badges: [Icons.mic_rounded, Icons.receipt_long]),
    ),
    const _Page(
      'Veja para onde vai o dinheiro',
      'Saldo de cada conta, gastos por categoria e orçamentos que avisam antes de você estourar o limite.',
      _Art(icon: Icons.pie_chart_rounded, color: Color(0xFF3B82F6), badges: [Icons.savings, Icons.trending_up]),
    ),
    const _Page(
      'Uma IA do seu lado',
      'Peça uma análise do mês, receba uma nota de saúde financeira e dicas do que dá para economizar.',
      _Art(icon: Icons.auto_awesome, color: Color(0xFF8B5CF6), badges: [Icons.lightbulb, Icons.emoji_events]),
    ),
  ];

  bool get _last => _page == _pages.length - 1;

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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedOpacity(
              opacity: _last ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: TextButton(
                onPressed: _last ? null : () => context.read<AppState>().completeOnboarding(),
                child: const Text('PULAR', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
              ),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (p) => setState(() => _page = p),
              children: [
                for (final p in _pages)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      p.art,
                      const SizedBox(height: 36),
                      Text(p.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.2)),
                      const SizedBox(height: 12),
                      Text(p.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, height: 1.5, color: cs.onSurfaceVariant)),
                    ]),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < _pages.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: i == _page ? 26 : 10,
                height: 10,
                decoration: BoxDecoration(
                  color: i == _page ? brandColor : cs.outlineVariant,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                ChunkyButton(label: _last ? 'Começar' : 'Continuar', onPressed: _next),
                SizedBox(
                  height: 48,
                  child: _last
                      ? TextButton(
                          onPressed: () => context.read<AppState>().completeOnboarding(signIn: true),
                          child: const Text('JÁ TENHO CONTA',
                              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
                        )
                      : null,
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Ilustração: círculo colorido com um ícone grande e dois "selos" flutuando.
class _Art extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final List<IconData> badges;
  final Widget? child;
  const _Art({this.icon, this.color = brandColor, this.badges = const [], this.child});

  @override
  Widget build(BuildContext context) {
    Widget badge(IconData i) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardTheme.color,
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Icon(i, color: color, size: 26),
        );
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: 210,
          height: 210,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: child != null
                  ? const [mar, tinta]
                  : [color.withValues(alpha: .9), Color.lerp(color, Colors.black, .2)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child ?? Icon(icon, size: 96, color: Colors.white),
        ),
        if (badges.isNotEmpty) Positioned(top: 8, right: 4, child: badge(badges[0])),
        if (badges.length > 1) Positioned(bottom: 10, left: 0, child: badge(badges[1])),
      ]),
    );
  }
}
