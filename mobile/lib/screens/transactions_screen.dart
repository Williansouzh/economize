import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/month_loader.dart';
import 'transaction_form_screen.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const MonthSelector(),
      Expanded(
        child: MonthLoader<(List<Transaction>, List<Transfer>)>(
          load: (s) async {
            final r = await Future.wait([s.api.transactions(s.monthKey), s.api.transfers(s.monthKey)]);
            return (r[0] as List<Transaction>, r[1] as List<Transfer>);
          },
          builder: (context, data, _) {
            final (txs, transfers) = data;
            if (txs.isEmpty && transfers.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 60),
                EmptyState(
                  icon: Icons.receipt_long,
                  title: 'Nenhum lançamento neste mês',
                  message: 'Toque em + para registrar uma receita ou despesa.',
                ),
              ]);
            }
            // Agrupa por dia, como no Organizze. Transferências aparecem no dia, mas não somam
            // nas entradas e saídas: só mudam o dinheiro de conta.
            final byDay = <DateTime, List<Object>>{};
            for (final t in txs) {
              byDay.putIfAbsent(t.date, () => []).add(t);
            }
            for (final t in transfers) {
              byDay.putIfAbsent(t.date, () => []).add(t);
            }
            final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
            double sum(Iterable<Object> l, TxType type) =>
                l.whereType<Transaction>().where((t) => t.type == type).fold(0.0, (a, t) => a + t.amount);
            final income = sum(txs, TxType.income), expenses = sum(txs, TxType.expense);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
              children: [
                _MonthSummary(income: income, expenses: expenses),
                for (final day in days) ...[
                  _DayHeader(day, sum(byDay[day]!, TxType.income) - sum(byDay[day]!, TxType.expense)),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      for (final (i, item) in byDay[day]!.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        switch (item) {
                          Transaction t => _TransactionTile(t),
                          Transfer t => _TransferTile(t),
                          _ => const SizedBox.shrink(),
                        },
                      ],
                    ]),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ]);
  }
}

class _MonthSummary extends StatelessWidget {
  final double income, expenses;
  const _MonthSummary({required this.income, required this.expenses});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, double v, Color color, IconData icon) => Expanded(
          child: Row(children: [
            IconBadge(icon, color, size: 34),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label,
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(money(v), style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                ),
              ]),
            ),
          ]),
        );
    final balance = income - expenses;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          item('Entradas', income, incomeColor, Icons.south_west),
          item('Saídas', expenses, expenseColor, Icons.north_east),
          item('Saldo', balance, balance >= 0 ? incomeColor : expenseColor, Icons.balance),
        ]),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final double total;
  const _DayHeader(this.day, this.total);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(day.year, day.month, day.day)).inDays;
    final label = switch (diff) {
      0 => 'Hoje',
      1 => 'Ontem',
      _ => DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(day),
    };
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(children: [
        Expanded(child: Text(label[0].toUpperCase() + label.substring(1), style: style)),
        Text('${total >= 0 ? '+' : '−'} ${money(total.abs())}', style: style),
      ]),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction t;
  const _TransactionTile(this.t);

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == TxType.income;
    final cs = Theme.of(context).colorScheme;
    final account = context.watch<AppState>().accounts.where((a) => a.id == t.accountId).firstOrNull;
    return _Deletable(
      id: t.id,
      title: 'Excluir lançamento?',
      content: t.description.isEmpty ? t.categoryName : t.description,
      onDelete: (api) => api.deleteTransaction(t.id),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => TransactionFormScreen(editing: t))),
        leading: IconBadge(categoryIcon(t.categoryIcon), hexColor(t.categoryColor)),
        title: Text(t.description.isEmpty ? t.categoryName : t.description,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(children: [
          Icon(accountIcon(account?.icon ?? ''), size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text('${t.categoryName} · ${t.accountName}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ),
        ]),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            '${isIncome ? '+' : '−'} ${money(t.amount)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: isIncome ? incomeColor : expenseColor),
          ),
          if (!t.isPaid) const _PendingBadge(),
        ]),
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  final Transfer t;
  const _TransferTile(this.t);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Deletable(
      id: t.id,
      title: 'Excluir transferência?',
      content: '${t.fromAccountName} → ${t.toAccountName}: ${money(t.amount)}',
      onDelete: (api) => api.deleteTransfer(t.id),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => TransactionFormScreen(editingTransfer: t))),
        leading: const IconBadge(Icons.swap_horiz, transferColor),
        title: Text(t.description.isEmpty ? 'Transferência' : t.description,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${t.fromAccountName} → ${t.toAccountName}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(money(t.amount), style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          if (!t.isPaid) const _PendingBadge(),
        ]),
      ),
    );
  }
}

class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: warningColor.withValues(alpha: .15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text('pendente',
            style: TextStyle(fontSize: 10, color: Color(0xFFB7791F), fontWeight: FontWeight.w600)),
      );
}

/// Arrastar para a esquerda pede confirmação e exclui.
class _Deletable extends StatelessWidget {
  final String id, title, content;
  final Future<void> Function(ApiClient api) onDelete;
  final Widget child;
  const _Deletable(
      {required this.id, required this.title, required this.content, required this.onDelete, required this.child});

  @override
  Widget build(BuildContext context) => Dismissible(
        key: ValueKey(id),
        direction: DismissDirection.endToStart,
        background: Container(
          color: expenseColor,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Excluir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            SizedBox(width: 8),
            Icon(Icons.delete_outline, color: Colors.white),
          ]),
        ),
        confirmDismiss: (_) => showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Icons.delete_outline, color: expenseColor),
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: expenseColor),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ),
        onDismissed: (_) async {
          final state = context.read<AppState>();
          try {
            await onDelete(state.api);
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
          state.dataChanged();
        },
        child: child,
      );
}
