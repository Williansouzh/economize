import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/month_loader.dart';
import 'account_sheet.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const MonthSelector(),
      Expanded(
        child: MonthLoader<Dashboard>(
          load: (s) => s.api.dashboard(s.monthKey),
          builder: (context, d, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
            children: [
              _BalanceCard(d),
              const SizedBox(height: 16),
              _MetricsGrid(d),
              const SizedBox(height: 16),
              _AccountsSection(d.accounts),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Despesas por categoria',
                child: d.expensesByCategory.isEmpty
                    ? const EmptyState(
                        icon: Icons.pie_chart_outline,
                        title: 'Nenhuma despesa neste mês',
                        message: 'Quando você lançar gastos, eles aparecem aqui por categoria.',
                      )
                    : _ExpensesChart(d.expensesByCategory, d.expenses),
              ),
              if (d.budgets.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Orçamentos',
                  child: Column(children: d.budgets.map((b) => BudgetProgress(b)).toList()),
                ),
              ],
            ],
          ),
        ),
      ),
    ]);
  }
}

class _BalanceCard extends StatelessWidget {
  final Dashboard d;
  const _BalanceCard(this.d);

  @override
  Widget build(BuildContext context) {
    final month = context.watch<AppState>().month;
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final text = Theme.of(context).textTheme;
    const white = Colors.white;
    final soft = white.withValues(alpha: .8);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF00C27C), brandDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: brandColor.withValues(alpha: .35), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance_wallet_outlined, color: soft, size: 18),
          const SizedBox(width: 6),
          Text('Saldo atual', style: TextStyle(color: soft, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(money(d.totalBalance),
              style: text.displaySmall?.copyWith(color: white, fontWeight: FontWeight.w800, letterSpacing: -.5)),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Previsto em ${DateFormat("d 'de' MMM", 'pt_BR').format(monthEnd)}: ${money(d.forecastBalance)}',
            style: const TextStyle(color: white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _Flow('Receitas', d.income, Icons.south_west)),
          Container(width: 1, height: 40, color: white.withValues(alpha: .25)),
          const SizedBox(width: 16),
          Expanded(child: _Flow('Despesas', d.expenses, Icons.north_east)),
        ]),
      ]),
    );
  }
}

class _Flow extends StatelessWidget {
  final String label;
  final double value;
  final IconData icon;
  const _Flow(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: .8))),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(value),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ]),
        ),
      ]);
}

/// Indicadores do mês calculados a partir do resumo: resultado, taxa de economia,
/// gasto médio por dia e o que ainda está pendente.
class _MetricsGrid extends StatelessWidget {
  final Dashboard d;
  const _MetricsGrid(this.d);

  @override
  Widget build(BuildContext context) {
    final month = context.watch<AppState>().month;
    final now = DateTime.now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final isCurrent = month.year == now.year && month.month == now.month;
    final days = isCurrent ? now.day : daysInMonth;
    final savingsRate = d.income > 0 ? d.monthResult / d.income : null;
    final top = d.expensesByCategory.isEmpty ? null : d.expensesByCategory.first;

    final tiles = [
      _MetricTile(
        icon: d.monthResult >= 0 ? Icons.trending_up : Icons.trending_down,
        color: d.monthResult >= 0 ? incomeColor : expenseColor,
        label: 'Resultado do mês',
        value: money(d.monthResult),
        hint: d.monthResult >= 0 ? 'Sobrou dinheiro' : 'Gastou mais do que ganhou',
      ),
      _MetricTile(
        icon: Icons.savings_outlined,
        color: savingsRate == null
            ? Colors.blueGrey
            : savingsRate >= .2
                ? incomeColor
                : savingsRate >= 0
                    ? warningColor
                    : expenseColor,
        label: 'Taxa de economia',
        value: savingsRate == null ? '—' : percent(savingsRate),
        hint: savingsRate == null ? 'Sem receitas no mês' : 'Meta saudável: 20%',
      ),
      _MetricTile(
        icon: Icons.calendar_today_outlined,
        color: const Color(0xFF3B82F6),
        label: 'Gasto médio por dia',
        value: money(days == 0 ? 0 : d.expenses / days),
        hint: top == null ? 'Nenhum gasto ainda' : 'Maior gasto: ${top.name}',
      ),
      _MetricTile(
        icon: Icons.schedule,
        color: const Color(0xFF8B5CF6),
        label: 'Pendentes',
        value: money(d.pendingExpenses),
        hint: 'a pagar · ${money(d.pendingIncome)} a receber',
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth > 700 ? 4 : 2;
      const gap = 12.0;
      final w = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: tiles.map((t) => SizedBox(width: w, child: t)).toList(),
      );
    });
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value, hint;
  const _MetricTile(
      {required this.icon, required this.color, required this.label, required this.value, required this.hint});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(icon, color, size: 36),
          const SizedBox(height: 12),
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _AccountsSection extends StatelessWidget {
  final List<Account> accounts;
  const _AccountsSection(this.accounts);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('Minhas contas',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        TextButton.icon(
          onPressed: () => showAccountSheet(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nova'),
        ),
      ]),
      const SizedBox(height: 4),
      SizedBox(
        height: 128,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: accounts.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, i) =>
              i < accounts.length ? _AccountCard(accounts[i]) : const _NewAccountCard(),
        ),
      ),
    ]);
  }
}

class _AccountCard extends StatelessWidget {
  final Account a;
  const _AccountCard(this.a);

  @override
  Widget build(BuildContext context) {
    final color = hexColor(a.color);
    final fg = onColor(color);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showAccountSheet(context, editing: a),
        child: Ink(
          width: 172,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [color, Color.lerp(color, Colors.black, .25)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(accountIcon(a.icon), color: fg, size: 24),
              const Spacer(),
              Icon(Icons.edit_outlined, color: fg.withValues(alpha: .6), size: 16),
            ]),
            const Spacer(),
            Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg.withValues(alpha: .85), fontWeight: FontWeight.w500)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(a.balance),
                  style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            if (a.forecastBalance != a.balance)
              Text('Previsto ${money(a.forecastBalance)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg.withValues(alpha: .75), fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

class _NewAccountCard extends StatelessWidget {
  const _NewAccountCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showAccountSheet(context),
      child: Container(
        width: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant, width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_circle_outline, color: cs.primary, size: 30),
          const SizedBox(height: 6),
          Text('Nova conta', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _ExpensesChart extends StatefulWidget {
  final List<CategoryTotal> items;
  final double total;
  const _ExpensesChart(this.items, this.total);
  @override
  State<_ExpensesChart> createState() => _ExpensesChartState();
}

class _ExpensesChartState extends State<_ExpensesChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppState>().categories;
    final cs = Theme.of(context).colorScheme;
    final items = widget.items;
    final selected = _touched != null && _touched! < items.length ? items[_touched!] : null;

    return Column(children: [
      SizedBox(
        height: 200,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            centerSpaceRadius: 64,
            sectionsSpace: 3,
            pieTouchData: PieTouchData(
              // Fora das fatias o índice vem -1.
              touchCallback: (event, res) {
                final i = res?.touchedSection?.touchedSectionIndex ?? -1;
                setState(() => _touched = event.isInterestedForInteractions && i >= 0 ? i : null);
              },
            ),
            sections: [
              for (var i = 0; i < items.length; i++)
                PieChartSectionData(
                  value: items[i].total,
                  color: hexColor(items[i].color),
                  radius: i == _touched ? 34 : 26,
                  showTitle: false,
                ),
            ],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(selected?.name ?? 'Total gasto',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            Text(money(selected?.total ?? widget.total),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      for (final c in items) ...[
        Row(children: [
          IconBadge(
            categoryIcon(categories.where((x) => x.id == c.categoryId).firstOrNull?.icon ?? ''),
            hexColor(c.color),
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(money(c.total), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: c.percent / 100,
                      minHeight: 6,
                      color: hexColor(c.color),
                      backgroundColor: hexColor(c.color).withValues(alpha: .12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  child: Text('${c.percent.round()}%',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
      ],
    ]);
  }
}

class BudgetProgress extends StatelessWidget {
  final Budget b;
  final VoidCallback? onTap;
  const BudgetProgress(this.b, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppState>().categories;
    final cs = Theme.of(context).colorScheme;
    final over = b.spent > b.limit;
    final base = hexColor(b.categoryColor);
    final color = over ? expenseColor : (b.progress > .8 ? warningColor : base);
    final icon = categoryIcon(categories.where((c) => c.id == b.categoryId).firstOrNull?.icon ?? '');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          IconBadge(icon, base, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text(b.categoryName, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (b.recurring) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Repete todo mês',
                    child: Icon(Icons.repeat, size: 14, color: cs.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                Text('${(b.progress * 100).round()}%',
                    style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: b.progress.clamp(0, 1),
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: .14),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                over
                    ? 'Estourou em ${money(b.spent - b.limit)}'
                    : '${money(b.spent)} de ${money(b.limit)} · restam ${money(b.limit - b.spent)}',
                style: TextStyle(fontSize: 12, color: over ? expenseColor : cs.onSurfaceVariant),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
