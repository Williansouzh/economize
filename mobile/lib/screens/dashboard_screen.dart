import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/month_loader.dart';
import 'transaction_form_screen.dart';

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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              _BalanceCard(d),
              const SizedBox(height: 12),
              _Section(
                title: 'Contas',
                child: Column(
                  children: d.accounts
                      .map<Widget>((a) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                                backgroundColor: hexColor(a.color),
                                child: const Icon(Icons.account_balance, color: Colors.white)),
                            title: Text(a.name),
                            subtitle: a.forecastBalance != a.balance
                                ? Text('Previsto: ${money(a.forecastBalance)}')
                                : null,
                            trailing: Text(money(a.balance),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: a.balance < 0 ? expenseColor : null)),
                          ))
                      .followedBy([
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _newAccount(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Nova conta'),
                      ),
                    ),
                  ]).toList(),
                ),
              ),
              const SizedBox(height: 12),
              _Section(
                title: 'Despesas por categoria',
                child: d.expensesByCategory.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16), child: Text('Nenhuma despesa neste mês.'))
                    : _ExpensesChart(d.expensesByCategory),
              ),
              if (d.budgets.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(
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

Future<void> _newAccount(BuildContext context) async {
  final state = context.read<AppState>();
  final name = TextEditingController();
  final balance = TextEditingController(text: '0,00');
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Nova conta'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome (ex.: Nubank)')),
        const SizedBox(height: 12),
        TextField(
          controller: balance,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(labelText: 'Saldo inicial', prefixText: 'R\$ '),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Criar')),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return;
  try {
    await state.api.createAccount(name.text.trim(), parseAmount(balance.text) ?? 0);
    state.dataChanged();
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _BalanceCard extends StatelessWidget {
  final Dashboard d;
  const _BalanceCard(this.d);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final month = context.watch<AppState>().month;
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final onCard = TextStyle(color: cs.onPrimaryContainer);
    final hasPending = d.pendingIncome > 0 || d.pendingExpenses > 0;
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Saldo atual', style: onCard),
          Text(money(d.totalBalance),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer)),
          Text('Só o que já foi pago ou recebido até hoje.',
              style: onCard.copyWith(fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            'Previsto em ${DateFormat("d 'de' MMMM", 'pt_BR').format(monthEnd)}: ${money(d.forecastBalance)}',
            style: onCard.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _Metric('Receitas', d.income, incomeColor, Icons.arrow_upward)),
            Expanded(child: _Metric('Despesas', d.expenses, expenseColor, Icons.arrow_downward)),
          ]),
          if (hasPending) ...[
            const SizedBox(height: 8),
            Text(
              'Pendentes no mês: a receber ${money(d.pendingIncome)} · a pagar ${money(d.pendingExpenses)}',
              style: onCard.copyWith(fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text('Resultado do mês: ${money(d.monthResult)}',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: d.monthResult >= 0 ? incomeColor : expenseColor)),
        ]),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;
  const _Metric(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) => Row(children: [
        CircleAvatar(radius: 16, backgroundColor: color, child: Icon(icon, size: 18, color: Colors.white)),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(money(value), style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      ]);
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}

class _ExpensesChart extends StatelessWidget {
  final List<CategoryTotal> items;
  const _ExpensesChart(this.items);

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(
          height: 180,
          child: PieChart(PieChartData(
            centerSpaceRadius: 50,
            sectionsSpace: 2,
            sections: items
                .map((c) => PieChartSectionData(
                      value: c.total,
                      color: hexColor(c.color),
                      radius: 32,
                      title: c.percent >= 8 ? '${c.percent.round()}%' : '',
                      titleStyle: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ))
                .toList(),
          )),
        ),
        const SizedBox(height: 8),
        ...items.map((c) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                CircleAvatar(radius: 6, backgroundColor: hexColor(c.color)),
                const SizedBox(width: 8),
                Expanded(child: Text(c.name)),
                Text('${money(c.total)}  ·  ${c.percent}%'),
              ]),
            )),
      ]);
}

class BudgetProgress extends StatelessWidget {
  final Budget b;
  final VoidCallback? onLongPress;
  const BudgetProgress(this.b, {super.key, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final over = b.spent > b.limit;
    final color = over ? expenseColor : (b.progress > .8 ? Colors.orange : hexColor(b.categoryColor));
    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(b.categoryName, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${money(b.spent)} de ${money(b.limit)}'),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: b.progress.clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            color: color,
          ),
          if (over)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Estourou em ${money(b.spent - b.limit)}',
                  style: const TextStyle(color: expenseColor, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
