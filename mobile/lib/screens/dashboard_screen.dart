import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/count_up.dart';
import '../widgets/month_loader.dart';
import '../widgets/playful.dart';
import 'account_sheet.dart';
import 'analysis_screen.dart';
import 'bank_notifications_screen.dart';
import 'home_screen.dart';
import 'invoice_screen.dart';
import 'profiles_screen.dart';
import 'transaction_form_screen.dart';
import 'whatsapp_screen.dart';

/// Dados do Início: o resumo do mês e os lançamentos (para o ritmo de gastos dia a dia).
typedef _HomeData = (Dashboard, List<Transaction>);

/// Início em uma tela e meia: saldo → ritmo do mês (ou teto do MEI) → 1 alerta do Cofrinho →
/// contas em lista → top 4 categorias com o orçamento embutido. O resto mora em Planejar e em "Seu mês".
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final business = context.select<AppState, bool>((s) => s.inBusinessProfile);
    return Column(
      children: [
        MonthSelector(onTapLabel: () => showProfileSheet(context)),
        Expanded(
          child: MonthLoader<_HomeData>(
            load: (s) async {
              final r = await Future.wait([s.dashboard(), s.monthEntries()]);
              return (r[0] as Dashboard, (r[1] as (List<Transaction>, List<Transfer>)).$1);
            },
            builder: (context, data, _) {
              final (d, txs) = data;
              final empty = txs.isEmpty;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  const DetectedBanner(),
                  _BalanceCard(d),
                  const _FirstSteps(),
                  if (business) ...[
                    const SizedBox(height: Space.lg),
                    const _MeiCeiling(),
                  ] else if (!empty) ...[
                    const SizedBox(height: Space.lg),
                    PaceCard(d, txs),
                  ],
                  if (_alertFor(context, d) case final alert?) ...[
                    const SizedBox(height: Space.lg),
                    alert,
                  ],
                  if (empty)
                    const EmptyState(
                      icon: Icons.receipt_long,
                      mascot: true,
                      title: 'Seu mês ainda está em branco',
                      message: 'Toque em Lançar, no meio da barra de baixo, ou mande o gasto no WhatsApp.',
                    ),
                  const SizedBox(height: Space.section),
                  _AccountsSection(d.accounts),
                  if (d.expensesByCategory.isNotEmpty) ...[
                    const SizedBox(height: Space.section),
                    _CategoriesSection(d),
                  ],
                  if (!empty) ...[
                    const SizedBox(height: Space.lg),
                    _MonthLines(d),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Saldo
// ---------------------------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  final Dashboard d;
  const _BalanceCard(this.d);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final month = state.month;
    final hidden = state.hideBalance;
    final business = state.inBusinessProfile;
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final soft = Colors.white.withValues(alpha: .78);
    final rate = d.income > 0 ? d.monthResult / d.income : null;
    String v(double x, {bool sign = false}) =>
        hidden ? '•••••' : '${sign ? (x < 0 ? '− ' : '+ ') : ''}${amountText(x.abs())}';

    return Container(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.sm, Space.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: brandGradient,
        boxShadow: context.isDark ? null : brandShadow,
        border: context.isDark ? Border.all(color: context.colors.cardBorder) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('Saldo nas contas', style: TextStyle(color: soft, fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          IconButton(
            tooltip: hidden ? 'Mostrar valores' : 'Esconder valores',
            onPressed: state.toggleHideBalance,
            icon: Icon(hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: Space.md),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: hidden
                ? const Text('R\$ •••••', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900))
                : CountUpMoney(
                    d.totalBalance,
                    memory: 'saldo:${state.api.profileId}',
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -.5),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Previsto em ${DateFormat("d 'de' MMM", 'pt_BR').format(monthEnd)}: ${hidden ? 'R\$ •••••' : money(d.forecastBalance)}',
          style: const TextStyle(color: lima, fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: Space.lg),
        Container(height: 1, margin: const EdgeInsets.only(right: Space.md), color: Colors.white.withValues(alpha: .18)),
        const SizedBox(height: Space.md),
        Row(children: [
          Expanded(child: _Flow(business ? 'Vendeu' : 'Entrou', v(d.income, sign: true))),
          Expanded(child: _Flow(business ? 'Custos' : 'Saiu', hidden ? '•••••' : '− ${amountText(d.expenses)}')),
          Expanded(
            child: _Flow(
              business ? 'Lucro' : 'Resultado',
              hidden ? '•••••' : '${v(d.monthResult, sign: true)}${rate == null ? '' : ' · ${percent(rate)}'}',
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Flow extends StatelessWidget {
  final String label, value;
  const _Flow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: .78))),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ]);
}

// ---------------------------------------------------------------------------------------------
// Ritmo do mês: gasto acumulado × linha do ritmo ideal (renda − meta de guardar 20%)
// ---------------------------------------------------------------------------------------------

/// O ritmo de gastos do mês. [ideal]: quanto dá para gastar no mês todo guardando 20% da renda.
class MonthPace {
  final List<double> cumulative; // gasto acumulado por dia (índice 0 = dia 1), até hoje
  final double spent, ideal, idealToDate;
  final int day, daysInMonth;
  const MonthPace(this.cumulative, this.spent, this.ideal, this.idealToDate, this.day, this.daysInMonth);

  bool get hasIdeal => ideal > 0;

  /// "ok" (no ritmo), "atencao" (até 10% acima) ou "acima".
  String get status => !hasIdeal || spent <= idealToDate ? 'ok' : (spent <= idealToDate * 1.1 ? 'atencao' : 'acima');

  static MonthPace of(Dashboard d, List<Transaction> txs, DateTime month, {double? declaredIncome}) {
    final now = DateTime.now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final isCurrent = month.year == now.year && month.month == now.month;
    final future = month.isAfter(DateTime(now.year, now.month));
    final day = future ? 0 : (isCurrent ? now.day : daysInMonth);
    final perDay = List<double>.filled(daysInMonth, 0);
    for (final t in txs) {
      if (t.type == TxType.expense && t.date.day <= day) perDay[t.date.day - 1] += t.amount;
    }
    final cumulative = <double>[];
    var acc = 0.0;
    for (var i = 0; i < day; i++) {
      acc += perDay[i];
      cumulative.add(acc);
    }
    final income = math.max(d.income + d.pendingIncome, declaredIncome ?? 0);
    final budgets = d.budgets.fold(0.0, (a, b) => a + b.limit);
    final ideal = income > 0 ? income * .8 : budgets;
    return MonthPace(cumulative, acc, ideal, ideal * day / daysInMonth, day, daysInMonth);
  }
}

class PaceCard extends StatelessWidget {
  final Dashboard d;
  final List<Transaction> txs;
  const PaceCard(this.d, this.txs, {super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pace = MonthPace.of(d, txs, state.month, declaredIncome: state.about?.monthlyIncome);
    final cs = Theme.of(context).colorScheme;
    final colors = context.colors;
    final (badge, badgeBg, badgeFg) = switch (pace.status) {
      'ok' => ('No ritmo', cs.primaryContainer, cs.onPrimaryContainer),
      'atencao' => ('Atenção', colors.warningSoft, colors.onWarningSoft),
      _ => ('Acima do ritmo', colors.warningSoft, colors.onWarningSoft),
    };
    final line = context.isDark ? lima : mar;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalysisScreen())),
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Ritmo do mês', style: Theme.of(context).textTheme.titleMedium)),
              if (pace.hasIdeal) StatusBadge(badge, background: badgeBg, foreground: badgeFg),
            ]),
            const SizedBox(height: Space.lg),
            SizedBox(
              height: 92,
              child: Semantics(
                label: 'Gráfico do gasto acumulado no mês comparado ao ritmo ideal',
                child: LineChart(
                  duration: const Duration(milliseconds: 450),
                  LineChartData(
                    minX: 1,
                    maxX: pace.daysInMonth.toDouble(),
                    minY: 0,
                    maxY: math.max(pace.ideal, pace.spent) * 1.1 + 1,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      if (pace.hasIdeal)
                        LineChartBarData(
                          spots: [const FlSpot(1, 0), FlSpot(pace.daysInMonth.toDouble(), pace.ideal)],
                          color: cs.onSurfaceVariant.withValues(alpha: .7),
                          barWidth: 1.5,
                          dashArray: [4, 4],
                          dotData: const FlDotData(show: false),
                        ),
                      LineChartBarData(
                        spots: [
                          const FlSpot(1, 0),
                          for (var i = 0; i < pace.cumulative.length; i++) FlSpot(i + 1.0, pace.cumulative[i]),
                        ],
                        color: line,
                        barWidth: 3,
                        isCurved: false,
                        dotData: FlDotData(
                          show: true,
                          checkToShowDot: (spot, bar) => spot.x == pace.cumulative.length,
                          getDotPainter: (_, _, _, _) =>
                              FlDotCirclePainter(radius: 5, color: line, strokeWidth: 0, strokeColor: line),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            Row(children: [
              Expanded(child: _Labeled(pace.day >= pace.daysInMonth ? 'Você gastou' : 'Gasto até hoje', moneyShort(pace.spent))),
              if (pace.hasIdeal)
                _Labeled(
                  pace.day >= pace.daysInMonth ? 'Ritmo ideal no mês' : 'Ritmo ideal até hoje',
                  moneyShort(pace.idealToDate),
                  end: true,
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  final String label, value;
  final bool end;
  const _Labeled(this.label, this.value, {this.end = false});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: valueStyle.copyWith(fontSize: 17)),
        ],
      );
}

// ---------------------------------------------------------------------------------------------
// Teto do MEI (2º bloco no perfil de empresa): faturado hoje · projeção em dezembro · teto
// ---------------------------------------------------------------------------------------------

class _MeiCeiling extends StatelessWidget {
  const _MeiCeiling();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final profile = state.activeProfile;
    if (profile == null || !profile.isMei) return const SizedBox.shrink();
    return FutureBuilder<MeiSummary>(
      key: ValueKey('${state.revision}#${state.month.year}#${profile.id}'),
      future: state.api.meiSummary(year: state.month.year),
      builder: (context, snap) {
        final m = snap.data;
        if (m == null) return const Card(child: SizedBox(height: 132));
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalysisScreen())),
            child: Padding(padding: const EdgeInsets.all(Space.xl), child: MeiCeilingBar(m)),
          ),
        );
      },
    );
  }
}

/// Barra de 12 dp do teto do MEI com três marcas: o faturado hoje, a projeção para dezembro e o teto.
class MeiCeilingBar extends StatelessWidget {
  final MeiSummary m;
  const MeiCeilingBar(this.m, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = context.colors;
    final color = switch (m.status) { 'estourou' => colors.expense, 'atencao' => colors.warning, _ => colors.success };
    final max = math.max(m.limit, m.projectedRevenue) * 1.05;
    final now = (m.revenue / max).clamp(0.0, 1.0);
    final projected = (m.projectedRevenue / max).clamp(0.0, 1.0);
    final limit = (m.limit / max).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Teto do MEI em ${m.year}', style: Theme.of(context).textTheme.titleMedium)),
        Text('${m.percent.toStringAsFixed(0)}%', style: valueStyle.copyWith(color: color)),
      ]),
      const SizedBox(height: Space.lg),
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        Widget tick(double x, Color color, {double h = 22}) =>
            Positioned(left: (w * x - 1).clamp(0, w - 2), top: 0, child: Container(width: 2, height: h, color: color));
        return SizedBox(
          height: 22,
          child: Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 12, decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
            // Projeção até dezembro: faixa clara da cor de status.
            FractionallySizedBox(
              widthFactor: projected,
              child: Container(height: 12, decoration: BoxDecoration(color: color.withValues(alpha: .25), borderRadius: BorderRadius.circular(6))),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: now),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => FractionallySizedBox(
                widthFactor: v,
                child: Container(height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
              ),
            ),
            tick(limit, cs.onSurface),
          ]),
        );
      }),
      const SizedBox(height: Space.sm),
      Row(children: [
        Expanded(child: Text('Faturado: ${moneyShort(m.revenue)}', style: Theme.of(context).textTheme.bodySmall)),
        Text('Em dez.: ${moneyShort(m.projectedRevenue)}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: Space.md),
        Text('Teto: ${moneyShort(m.limit)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface)),
      ]),
      const SizedBox(height: Space.md),
      Text(
        m.status == 'estourou'
            ? 'Passou do teto. Até 20% acima você paga a diferença e vira microempresa no ano que vem; fale com um contador.'
            : m.monthsLeft > 0
                ? 'Pode faturar até ${perMonth(m.monthlyRoom)} até dezembro sem passar do teto.'
                : 'O ano fecha em ${moneyShort(m.revenue)}, dentro do teto.',
        style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------
// Um alerta do Cofrinho (o mais importante do momento)
// ---------------------------------------------------------------------------------------------

Widget? _alertFor(BuildContext context, Dashboard d) {
  final state = context.read<AppState>();
  final month = state.month;
  final monthEnd = DateTime(month.year, month.month + 1, 0);
  final budgets = [...d.budgets]..sort((a, b) => b.progress.compareTo(a.progress));
  final top = budgets.firstOrNull;
  if (top != null && top.progress >= 1) {
    return _CofrinhoAlert(
      title: 'Passou do limite · ${top.categoryName}',
      text: 'Passou ${money(top.spent - top.limit)} do combinado. Quer rever o limite ou segurar até o fim do mês?',
      worried: true,
      onTap: () => HomeScreenState.openTab(context, 3),
    );
  }
  if (top != null && top.progress >= .8) {
    return _CofrinhoAlert(
      title: 'Atenção · ${top.categoryName}',
      text: '${(top.progress * 100).round()}% do limite usado. '
          'Restam ${money(top.limit - top.spent)} até o dia ${monthEnd.day}.',
      onTap: () => HomeScreenState.openTab(context, 3),
    );
  }
  final wallet = d.accounts.where((a) => !a.isCard && a.balance < 0).firstOrNull;
  if (wallet != null) {
    return _CofrinhoAlert(
      title: '${wallet.name} no negativo',
      text: 'O saldo está em ${money(wallet.balance)}. Dinheiro vivo negativo costuma ser lançamento na conta errada.',
      onTap: () => showAccountSheet(context, editing: wallet),
    );
  }
  return null;
}

class _CofrinhoAlert extends StatelessWidget {
  final String title, text;
  final VoidCallback onTap;
  final bool worried;
  const _CofrinhoAlert({required this.title, required this.text, required this.onTap, this.worried = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.warningSoft,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Row(children: [
            if (worried)
              const MascotAvatar(size: 44, pose: MascotPose.worried)
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
                child: Icon(Icons.warning_amber_rounded, color: colors.onWarningSoft),
              ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: colors.onWarningSoft)),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(height: 1.35, color: Theme.of(context).colorScheme.onSurface)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onWarningSoft),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Primeiros passos: lançar o 1º gasto · conectar o WhatsApp · criar 1 orçamento
// ---------------------------------------------------------------------------------------------

class _FirstSteps extends StatefulWidget {
  const _FirstSteps();
  @override
  State<_FirstSteps> createState() => _FirstStepsState();
}

class _FirstStepsState extends State<_FirstSteps> {
  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    if (!state.firstStepsHidden && !state.whatsAppChecked) state.loadWhatsApp();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.firstStepsHidden || state.inBusinessProfile) return const SizedBox.shrink();
    return FutureBuilder<Progress>(
      key: ValueKey(state.revision),
      future: state.progress(),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null || !state.whatsAppChecked) return const SizedBox.shrink();
        bool done(String id) => p.achievements.any((a) => a.id == id && a.unlocked);
        final mei = state.about?.sources.contains('mei') == true && !state.profiles.any((x) => x.isBusiness);
        final steps = <(String, bool, VoidCallback)>[
          ('Lançar o primeiro gasto', done('first_entry'), () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionFormScreen()));
          }),
          ('Conectar o WhatsApp', state.whatsAppPhone != null, () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatsAppScreen()));
            state.loadWhatsApp();
          }),
          ('Criar um orçamento', done('budget_set'), () => HomeScreenState.openTab(context, 3)),
          if (mei) ('Criar o perfil da empresa', false, () => createBusinessProfile(context)),
        ];
        final count = steps.where((s) => s.$2).length;
        if (count == steps.length) {
          // Tudo feito: some sozinho na próxima vez.
          WidgetsBinding.instance.addPostFrameCallback((_) => state.hideFirstSteps());
          return const SizedBox.shrink();
        }
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.sm, Space.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('Primeiros passos', style: Theme.of(context).textTheme.titleMedium)),
                  Text('$count/${steps.length}', style: valueStyle.copyWith(fontSize: 14, color: cs.onSurfaceVariant)),
                  IconButton(
                    tooltip: 'Esconder',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: state.hideFirstSteps,
                  ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(right: Space.md, bottom: Space.sm),
                  child: StatusBar(value: count / steps.length, color: cs.primary),
                ),
                for (final (label, ok, onTap) in steps)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: ok ? null : onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: ok ? context.colors.success : cs.outline),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(label,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: ok ? cs.onSurfaceVariant : cs.onSurface,
                                decoration: ok ? TextDecoration.lineThrough : null,
                              )),
                        ),
                        if (!ok) Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                        const SizedBox(width: Space.sm),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Contas e cartões em lista compacta
// ---------------------------------------------------------------------------------------------

class _AccountsSection extends StatefulWidget {
  final List<Account> accounts;
  const _AccountsSection(this.accounts);
  @override
  State<_AccountsSection> createState() => _AccountsSectionState();
}

class _AccountsSectionState extends State<_AccountsSection> {
  bool _all = false;
  static const _visible = 3;

  @override
  Widget build(BuildContext context) {
    final accounts = widget.accounts;
    final shown = _all ? accounts : accounts.take(_visible).toList();
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(
        'Contas e cartões',
        action: accounts.length > _visible
            ? TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Ver menos' : 'Ver as ${accounts.length}'),
              )
            : null,
      ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(children: [
            for (final (i, a) in shown.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 72),
              AccountRow(a),
            ],
            if (shown.isNotEmpty) const Divider(height: 1, indent: 72),
            ListTile(
              minTileHeight: 56,
              leading: SizedBox(width: 40, child: Icon(Icons.add_rounded, color: cs.primary)),
              title: Text('Nova conta ou cartão', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800)),
              onTap: () => showAccountSheet(context),
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// Linha de conta ou cartão: ícone tingido, nome, detalhe (fatura ou previsto) e o valor à direita.
class AccountRow extends StatelessWidget {
  final Account a;
  const AccountRow(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final hidden = state.hideBalance;
    final colors = context.colors;
    final cs = Theme.of(context).colorScheme;
    String? detail;
    Color? detailColor;
    if (a.isCard) {
      final now = DateTime.now();
      if (a.closingDay != null) {
        var closing = DateTime(now.year, now.month, a.closingDay!);
        if (!closing.isAfter(DateTime(now.year, now.month, now.day))) closing = DateTime(now.year, now.month + 1, a.closingDay!);
        detail = 'Fatura fecha em ${DateFormat("d 'de' MMM", 'pt_BR').format(closing)}';
      }
    } else if (a.balance < 0 && !a.isCard) {
      detail = 'Saldo negativo: confira os lançamentos';
      detailColor = colors.expense;
    } else if (a.forecastBalance != a.balance) {
      detail = 'Previsto ${hidden ? 'R\$ •••••' : money(a.forecastBalance)}';
    }
    final value = a.isCard ? (a.openInvoice ?? 0) : a.balance;
    return ListTile(
      minTileHeight: 64,
      leading: IconBadge(accountIcon(a.icon), tintOf(context, a.color)),
      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: detail == null
          ? null
          : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: detailColor)),
      trailing: Text(
        hidden ? 'R\$ •••••' : money(value),
        style: valueStyle.copyWith(color: !a.isCard && a.balance < 0 ? colors.expense : cs.onSurface),
      ),
      // Cartão abre a fatura (a edição fica no lápis de lá); conta comum abre a edição.
      onTap: () => a.isCard
          ? Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(account: a)))
          : showAccountSheet(context, editing: a),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Gastos por categoria: barras horizontais ranqueadas (top 4 + Outras) com o orçamento embutido
// ---------------------------------------------------------------------------------------------

class _CategoriesSection extends StatelessWidget {
  final Dashboard d;
  const _CategoriesSection(this.d);

  @override
  Widget build(BuildContext context) {
    final items = d.expensesByCategory;
    final top = items.take(4).toList();
    final rest = items.skip(4).fold(0.0, (a, c) => a + c.total);
    final max = items.isEmpty ? 1.0 : items.first.total;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(
        context.select<AppState, bool>((s) => s.inBusinessProfile) ? 'Custos do mês' : 'Gastos do mês',
        action: TextButton(onPressed: () => HomeScreenState.openTab(context, 3), child: const Text('Orçamentos')),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.sm),
          child: Column(children: [
            for (final c in top)
              CategoryBar(
                total: c,
                max: max,
                budget: d.budgets.where((b) => b.categoryId == c.categoryId).firstOrNull,
              ),
            if (rest > 0) _OthersRow(rest, max),
          ]),
        ),
      ),
    ]);
  }
}

/// Uma categoria do mês: nome e valor; barra no tamanho relativo à maior categoria. Com orçamento,
/// a barra vira o progresso do limite, na cor de status, com o marcador de "hoje".
class CategoryBar extends StatelessWidget {
  final CategoryTotal total;
  final double max;
  final Budget? budget;
  const CategoryBar({super.key, required this.total, required this.max, this.budget});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final colors = context.colors;
    final cs = Theme.of(context).colorScheme;
    final category = state.categories.where((x) => x.id == total.categoryId).firstOrNull;
    final tint = tintOf(context, total.color);
    final b = budget;
    final now = DateTime.now();
    final month = state.month;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final isCurrent = month.year == now.year && month.month == now.month;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        IconBadge(categoryIcon(category?.icon ?? ''), tint),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(total.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              Text(moneyShort(total.total), style: valueStyle),
            ]),
            const SizedBox(height: 6),
            StatusBar(
              value: b == null ? total.total / max : b.progress,
              // Sem orçamento, barra neutra: cor de categoria só no ícone (âmbar não pode parecer alerta).
              color: b == null ? cs.outline : colors.forProgress(b.progress),
              marker: b != null && isCurrent ? now.day / daysInMonth : null,
            ),
            if (b != null) ...[
              const SizedBox(height: 2),
              Text(
                b.spent > b.limit
                    ? 'Passou ${moneyShort(b.spent - b.limit)} do limite de ${moneyShort(b.limit)}'
                    : 'Restam ${moneyShort(b.limit - b.spent)} de ${moneyShort(b.limit)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: b.progress >= .8 ? colors.forProgress(b.progress) : cs.onSurfaceVariant,
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _OthersRow extends StatelessWidget {
  final double value, max;
  const _OthersRow(this.value, this.max);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        IconBadge(Icons.more_horiz_rounded, cs.onSurfaceVariant),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Expanded(child: Text('Outras', style: TextStyle(fontWeight: FontWeight.w700))),
              Text(moneyShort(value), style: valueStyle),
            ]),
            const SizedBox(height: 6),
            StatusBar(value: value / max, color: cs.outline),
          ]),
        ),
      ]),
    );
  }
}

/// O que antes eram mini-cards: gasto médio por dia e pendentes, como linhas.
class _MonthLines extends StatelessWidget {
  final Dashboard d;
  const _MonthLines(this.d);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final month = state.month;
    final now = DateTime.now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final isCurrent = month.year == now.year && month.month == now.month;
    final days = isCurrent ? now.day : daysInMonth;
    final hidden = state.hideBalance;
    String v(double x) => hidden ? 'R\$ •••••' : money(x);
    return Card(
      child: Column(children: [
        ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Gasto médio por dia'),
          trailing: Text(v(days == 0 ? 0 : d.expenses / days), style: valueStyle),
        ),
        if (d.pendingExpenses > 0 || d.pendingIncome > 0) ...[
          const Divider(height: 1, indent: 56),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Pendentes'),
            subtitle: d.pendingIncome > 0 ? Text('${v(d.pendingIncome)} a receber') : null,
            trailing: Text('${v(d.pendingExpenses)} a pagar', style: valueStyle.copyWith(fontSize: 15)),
            onTap: () => HomeScreenState.openTab(context, 1),
          ),
        ],
      ]),
    );
  }
}
