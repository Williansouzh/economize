import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/about_fields.dart';
import '../widgets/common.dart';
import '../widgets/count_up.dart';
import '../widgets/playful.dart';
import '../widgets/situation.dart';

/// Situação financeira: a do mês (lançamentos) e o ponto de partida (questionário), comparado com
/// a renda de quem tem a mesma idade no Brasil (RN-46). No perfil de empresa, só o mês e o teto do MEI.
class AnalysisScreen extends StatelessWidget {
  final bool initialFirst;
  const AnalysisScreen({super.key, this.initialFirst = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final business = state.inBusinessProfile;
    if (business) {
      return Scaffold(
        appBar: AppBar(title: Text('Situação de ${state.activeProfile?.name ?? 'empresa'}')),
        body: const _MonthTab(),
      );
    }
    return DefaultTabController(
      length: 2,
      initialIndex: initialFirst ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sua situação'),
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
      const MonthSelector(),
      Expanded(
        child: FutureBuilder<Analysis>(
          key: ValueKey('${state.monthKey}#${state.revision}'),
          future: state.monthlyAnalysis(),
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: () => state.dataChanged());
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [AnalysisView(snap.data!)]);
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
            const SizedBox(height: 12),
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

/// Análise completa: destaque com a situação, números do mês, comparação com o IBGE, teto do MEI e pontos.
class AnalysisView extends StatelessWidget {
  final Analysis a;
  const AnalysisView(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final style = situationStyle(a.status);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Hero(a, style.color, style.icon, style.label),
      if (a.kind == 'monthly' && (a.income ?? 0) + (a.expenses ?? 0) > 0) ...[
        const SizedBox(height: 12),
        _MonthNumbers(a),
      ],
      if (a.benchmark != null && a.status != 'sem_dados') ...[
        const SizedBox(height: 12),
        BenchmarkCard(a.benchmark!, income: a.income),
      ],
      if (a.mei != null) ...[
        const SizedBox(height: 12),
        MeiCard(a.mei!),
      ],
      if (a.points.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(children: [
              for (final p in a.points)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    IconBadge(analysisIcon(p.icon), toneColor(p.tone), size: 34),
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (_, t, child) => Transform.scale(scale: .92 + .08 * t, child: Opacity(opacity: t.clamp(0, 1), child: child)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: .35), width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
              child: Text(label.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: .8)),
            ),
          ]),
          const SizedBox(height: 14),
          Text(a.headline, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.2)),
          const SizedBox(height: 6),
          Text(a.message, style: TextStyle(fontSize: 15, height: 1.45, color: cs.onSurface)),
        ]),
      ),
    );
  }
}

class _MonthNumbers extends StatelessWidget {
  final Analysis a;
  const _MonthNumbers(this.a);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget cell(String label, double value, Color color, {bool pct = false}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: CountUpMoney(value,
                  format: pct ? percent : money,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
            ),
          ]),
        );
    final rate = a.savingsRate;
    final business = context.watch<AppState>().inBusinessProfile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          cell(business ? 'Vendeu' : 'Entrou', a.income ?? 0, incomeColor),
          cell(business ? 'Custos' : 'Saiu', a.expenses ?? 0, expenseColor),
          if (rate != null) cell(business ? 'Margem' : 'Guardou', rate, rate >= .2 ? incomeColor : rate >= 0 ? warningColor : expenseColor, pct: true),
        ]),
      ),
    );
  }
}

/// Onde a renda fica em relação à mediana e à média de quem tem a mesma idade no Brasil.
class BenchmarkCard extends StatelessWidget {
  final Benchmark b;
  final double? income;
  const BenchmarkCard(this.b, {super.key, this.income});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final you = income ?? 0;
    final max = [b.mean * 1.5, you * 1.15, b.median * 2.0].reduce((x, y) => x > y ? x : y);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const IconBadge(Icons.groups_rounded, Color(0xFF3B82F6), size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Você e quem tem ${b.ageGroupLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ]),
          if (b.percentile != null) ...[
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: b.percentile!.toDouble()),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Text('${v.round()}%',
                    style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1, color: mar)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('das pessoas dessa idade que trabalham ganham menos que você',
                      style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600, height: 1.3)),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 18),
          _Scale(max: max, marks: [
            ('Mediana', b.median.toDouble(), cs.onSurfaceVariant),
            ('Média', b.mean.toDouble(), const Color(0xFF3B82F6)),
            if (you > 0) ('Você', you, mar),
          ]),
          const SizedBox(height: 12),
          Text(
            'Metade das pessoas de ${b.ageGroupLabel} ganha até ${money(b.median.toDouble())}. '
            'A média (${money(b.mean.toDouble())}) é maior porque poucas pessoas ganham muito.'
            '${b.hasRegion ? ' No ${b.regionName}, a média é ${money(b.regionMean.toDouble())}.' : ''}',
            style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text('Fonte: ${b.source}.', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// Régua horizontal com marcadores que deslizam até o lugar.
class _Scale extends StatelessWidget {
  final double max;
  final List<(String, double, Color)> marks;
  const _Scale({required this.max, required this.marks});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 80,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 0,
            right: 0,
            top: 28,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(colors: [cs.surfaceContainerHighest, mar.withValues(alpha: .5)]),
              ),
            ),
          ),
          for (final (i, (label, value, color)) in marks.indexed)
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (value / max).clamp(0, 1)),
              duration: Duration(milliseconds: 900 + 150 * i),
              curve: Curves.easeOutCubic,
              builder: (_, t, _) {
                final x = (t * w).clamp(0.0, w);
                final above = label == 'Você';
                // Mediana e média costumam ficar perto: a média desce uma linha para os rótulos não se encostarem.
                final low = label == 'Média';
                return Positioned(
                  left: (x - 40).clamp(-8.0, w - 72),
                  top: above ? 0 : 38,
                  width: 80,
                  child: Column(children: [
                    if (!above) Container(width: 3, height: low ? 24 : 10, color: color),
                    Text(label,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
                    if (above) Container(width: 14, height: 14, margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5))),
                  ]),
                );
              },
            ),
        ]),
      );
    });
  }
}

/// Faturamento do ano do MEI em relação ao teto.
class MeiCard extends StatelessWidget {
  final MeiSummary m;
  const MeiCard(this.m, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (m.status) { 'estourou' => expenseColor, 'atencao' => warningColor, _ => incomeColor };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconBadge(Icons.speed_rounded, color, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Teto do MEI em ${m.year}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            Text('${m.percent.toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          ]),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (m.revenue / m.limit).clamp(0, 1)),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: v, minHeight: 14, color: color, backgroundColor: color.withValues(alpha: .14)),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('Faturado: ${money(m.revenue)}', style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('de ${money(m.limit)}', style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 8),
          Text(
            m.status == 'estourou'
                ? 'Passou do teto. Até 20% acima (R\$ 97.200) você paga a diferença e vira microempresa no ano que vem; fale com um contador.'
                : 'No ritmo atual, o ano fecha em ${money(m.projectedRevenue)}. '
                    '${m.monthsLeft > 0 ? 'Para ficar no teto, fature até ${money(m.monthlyRoom)} por mês até dezembro.' : ''}',
            style: TextStyle(fontSize: 13, height: 1.4, color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
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
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
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
        ChunkyButton(label: 'Salvar', busy: _busy, onPressed: _draft.validYear ? _save : null),
      ]),
    );
  }
}

/// Resumo da situação do mês no Início, com toque para a análise completa.
class SituationCard extends StatelessWidget {
  const SituationCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return FutureBuilder<Analysis>(
      key: ValueKey('${state.monthKey}#${state.revision}#${state.api.profileId}'),
      future: state.monthlyAnalysis(),
      builder: (context, snap) {
        final a = snap.data;
        if (a == null) return const SizedBox.shrink();
        final style = situationStyle(a.status);
        final cs = Theme.of(context).colorScheme;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalysisScreen())),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: style.color.withValues(alpha: .14), shape: BoxShape.circle),
                  child: Icon(style.icon, color: style.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a.headline, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(a.message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.3)),
                    if (a.mei case final mei?) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (mei.revenue / mei.limit).clamp(0, 1),
                              minHeight: 6,
                              color: mei.status == 'ok' ? mar : warningColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${mei.percent.toStringAsFixed(0)}% do teto do MEI',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                      ]),
                    ],
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ]),
            ),
          ),
        );
      },
    );
  }
}
