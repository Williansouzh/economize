import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/about_fields.dart';
import '../widgets/common.dart';
import '../widgets/month_loader.dart';
import '../widgets/playful.dart';
import '../widgets/situation.dart';
import 'dashboard_screen.dart';

/// "Seu mês": a situação do mês (lançamentos + ritmo + o resumo do Cofrinho, gerado em segundo plano)
/// e o ponto de partida (questionário), comparado com quem tem a mesma idade no Brasil (RN-46).
/// No perfil de empresa, só o mês e o teto do MEI.
class AnalysisScreen extends StatelessWidget {
  final bool initialFirst;
  const AnalysisScreen({super.key, this.initialFirst = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.inBusinessProfile) {
      return Scaffold(
        appBar: AppBar(title: Text(state.activeProfile?.name ?? 'Sua empresa')),
        body: const _MonthTab(),
      );
    }
    return DefaultTabController(
      length: 2,
      initialIndex: initialFirst ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Seu mês'),
          bottom: const TabBar(tabs: [Tab(text: 'Este mês'), Tab(text: 'Ponto de partida')]),
        ),
        body: const TabBarView(children: [_MonthTab(), _InitialTab()]),
      ),
    );
  }
}

class _MonthTab extends StatelessWidget {
  const _MonthTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(children: [
      const SizedBox(height: 8),
      const MonthSelector(),
      Expanded(
        child: MonthLoader<(Analysis, Dashboard, List<Transaction>)>(
          load: (s) async {
            final r = await Future.wait([s.monthlyAnalysis(), s.dashboard(), s.monthEntries()]);
            final txs = (r[2] as (List<Transaction>, List<Transfer>)).$1;
            // Resumo da IA pronto ao abrir (uma vez por dia; só depois do consentimento).
            if (!s.inBusinessProfile && txs.isNotEmpty) s.dailyInsights(entries: txs.length).ignore();
            return (r[0] as Analysis, r[1] as Dashboard, txs);
          },
          builder: (context, data, _) {
            final (a, d, txs) = data;
            final insights = state.insightsFor(state.monthKey);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
              AnalysisView(a),
              if (!state.inBusinessProfile && txs.isNotEmpty) ...[
                const SizedBox(height: Space.lg),
                PaceCard(d, txs),
              ],
              if (insights != null) ...[
                const SizedBox(height: Space.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const MascotAvatar(size: 32),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Resumo do Cofrinho', style: Theme.of(context).textTheme.titleMedium)),
                        Text('${insights.healthScore}/100', style: valueStyle),
                      ]),
                      const SizedBox(height: 8),
                      Text(insights.summary, style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
            ]);
          },
        ),
      ),
    ]);
  }
}

class _InitialTab extends StatefulWidget {
  const _InitialTab();
  @override
  State<_InitialTab> createState() => _InitialTabState();
}

class _InitialTabState extends State<_InitialTab> {
  late Future<Analysis> _future = context.read<AppState>().api.initialAnalysis();

  @override
  Widget build(BuildContext context) => FutureBuilder<Analysis>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorView(
                error: snap.error!,
                onRetry: () => setState(() => _future = context.read<AppState>().api.initialAnalysis()));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(padding: const EdgeInsets.all(16), children: [
            AnalysisView(snap.data!),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
                if (mounted) setState(() => _future = context.read<AppState>().api.initialAnalysis());
              },
              icon: const Icon(Icons.edit_outlined),
              label: Text(snap.data!.status == 'sem_dados' ? 'Responder o questionário' : 'Atualizar minhas respostas'),
            ),
          ]);
        },
      );
}

/// Análise: destaque com a situação, comparação com o IBGE, teto do MEI e pontos.
class AnalysisView extends StatelessWidget {
  final Analysis a;
  const AnalysisView(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final style = situationStyle(context, a.status);
    // O parágrafo da mediana já está no cartão do IBGE: não repete na lista de pontos.
    final points = a.benchmark == null
        ? a.points
        : a.points.where((p) => !(p.icon == 'bar_chart' && p.text.contains('mediana'))).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Hero(a, style.color, style.icon, style.label),
      if (a.benchmark != null && a.status != 'sem_dados') ...[
        const SizedBox(height: 12),
        BenchmarkCard(a.benchmark!, income: a.income),
      ],
      if (a.mei != null) ...[
        const SizedBox(height: 12),
        MeiCard(a.mei!),
      ],
      if (points.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(children: [
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    IconBadge(analysisIcon(p.icon), toneColor(context, p.tone), size: 36),
                    const SizedBox(width: 12),
                    Expanded(child: Text(p.text, style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600))),
                  ]),
                ),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _Hero extends StatelessWidget {
  final Analysis a;
  final Color color;
  final IconData icon;
  final String label;
  const _Hero(this.a, this.color, this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconBadge(icon, color, size: 40),
            const SizedBox(width: 10),
            StatusBadge(label, background: color.withValues(alpha: context.isDark ? .22 : .12), foreground: color),
          ]),
          const SizedBox(height: 14),
          Text(a.headline, style: Theme.of(context).textTheme.headlineSmall?.copyWith(height: 1.2)),
          const SizedBox(height: 6),
          Text(a.message, style: TextStyle(fontSize: 15, height: 1.45, color: cs.onSurface)),
        ]),
      ),
    );
  }
}

/// Onde a renda fica em relação a quem tem a mesma idade no Brasil, em linguagem de leigo:
/// frase-título ("9 em cada 10"), bonecos e uma régua com R$ nos marcadores. Média só no "Saiba mais".
class BenchmarkCard extends StatelessWidget {
  final Benchmark b;
  final double? income;
  const BenchmarkCard(this.b, {super.key, this.income});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final you = income ?? 0;
    final p = b.percentile;
    final tenths = p == null ? null : (p / 10).round().clamp(0, 10);
    // Sem ranking negativo: com menos de 3 em 10, a frase fala do ponto de partida, sem bonecos.
    final showRank = tenths != null && tenths >= 3;
    final title = showRank
        ? 'Você ganha mais que $tenths em cada 10 pessoas de ${b.ageGroupLabel}.'
        : 'Metade das pessoas de ${b.ageGroupLabel} ganha até ${moneyShort(b.median.toDouble())}.';
    final max = [b.median * 2.0, you * 1.15, b.mean * 1.3].reduce((x, y) => x > y ? x : y);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(height: 1.25)),
          if (showRank) ...[
            const SizedBox(height: 14),
            Semantics(
              label: '$tenths de 10 pessoas',
              excludeSemantics: true,
              child: Row(children: [
                for (var i = 0; i < 10; i++)
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: i < tenths ? 1 : 0),
                      duration: Duration(milliseconds: 250 + 40 * i),
                      builder: (_, v, _) => Icon(Icons.person_rounded,
                          size: 28, color: Color.lerp(cs.surfaceContainerHighest, cs.primary, v)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Text('$p% das pessoas dessa idade que trabalham ganham menos que você', style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 18),
          _Scale(max: max, median: b.median.toDouble(), you: you),
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text('Saiba mais', style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary, fontSize: 15)),
              children: [
                Text(
                  'Metade das pessoas de ${b.ageGroupLabel} ganha até ${money(b.median.toDouble())} (a mediana). '
                  'A média é ${money(b.mean.toDouble())}: ela é maior porque poucas pessoas ganham muito.'
                  '${b.hasRegion ? ' No ${b.regionName}, a média é ${money(b.regionMean.toDouble())}.' : ''}',
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 6),
                Text('Fonte: ${b.source}.', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Régua com R$ nos marcadores: "Metade ganha até R$ 2.500" embaixo e "Você: R$ 7.200" em cima.
class _Scale extends StatelessWidget {
  final double max, median, you;
  const _Scale({required this.max, required this.median, required this.you});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      Widget marker(double value, Widget label, {required bool above}) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (value / max).clamp(0, 1)),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, t, _) {
              final x = t * w;
              const width = 150.0;
              return Positioned(
                left: (x - width / 2).clamp(0.0, w - width),
                top: above ? 0 : 40,
                width: width,
                child: Column(children: [
                  if (above) label,
                  Container(width: 2, height: 12, color: above ? cs.primary : cs.onSurfaceVariant),
                  if (!above) label,
                ]),
              );
            },
          );
      return SizedBox(
        height: 84,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 34,
            child: Container(
              height: 8,
              decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          marker(median,
              Text('Metade ganha até ${moneyShort(median)}',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
              above: false),
          if (you > 0)
            marker(
                you,
                Text('Você: ${moneyShort(you)}',
                    textAlign: TextAlign.center, style: valueStyle.copyWith(fontSize: 14, color: cs.primary)),
                above: true),
        ]),
      );
    });
  }
}

/// Faturamento do ano do MEI em relação ao teto (mesma barra do Início).
class MeiCard extends StatelessWidget {
  final MeiSummary m;
  const MeiCard(this.m, {super.key});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(Space.xl), child: MeiCeilingBar(m)),
      );
}

/// Editar as respostas do questionário (quem já passou do onboarding).
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final _draft = AboutDraft(context.read<AppState>().about);
  bool _busy = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_draft.validYear) return;
    if (!await confirmLowIncome(context, _draft) || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<AppState>().saveAbout(
            birthYear: _draft.year,
            state: _draft.state,
            sources: _draft.sources.toList(),
            jobCount: _draft.jobCount,
            monthlyIncome: _draft.monthlyIncome,
            mainGoal: _draft.goal,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    void changed() => setState(() {});
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: Space.section),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            child,
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Sobre você')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MascotAvatar(size: 56),
          Expanded(
            child: SpeechBubble(
              tailLeft: true,
              child: Text('Com isso eu comparo sua situação com a de quem tem a sua idade. Fica só entre a gente. 🔒',
                  style: TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        section('Idade e estado', AgeFields(_draft, onChanged: changed)),
        section('De onde vem o seu dinheiro', SourcesFields(_draft, onChanged: changed)),
        section('Renda e objetivo', IncomeGoalFields(_draft, onChanged: changed)),
        FilledButton(onPressed: _draft.validYear && !_busy ? _save : null, child: const Text('Salvar')),
      ]),
    );
  }
}
