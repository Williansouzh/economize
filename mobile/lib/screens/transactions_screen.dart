import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
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
        child: MonthLoader<List<Transaction>>(
          load: (s) => s.api.transactions(s.monthKey),
          builder: (context, txs, _) {
            if (txs.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 120),
                Center(child: Text('Nenhum lançamento neste mês.\nToque em + para adicionar.',
                    textAlign: TextAlign.center)),
              ]);
            }
            // Agrupa por dia, como no Organizze.
            final byDay = <DateTime, List<Transaction>>{};
            for (final t in txs) {
              byDay.putIfAbsent(t.date, () => []).add(t);
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final entry in byDay.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(entry.key),
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                  ...entry.value.map((t) => _TransactionTile(t)),
                ],
              ],
            );
          },
        ),
      ),
    ]);
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction t;
  const _TransactionTile(this.t);

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == TxType.income;
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: expenseColor,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Excluir lançamento?'),
          content: Text(t.description),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Excluir')),
          ],
        ),
      ),
      onDismissed: (_) async {
        final state = context.read<AppState>();
        try {
          await state.api.deleteTransaction(t.id);
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
        state.dataChanged();
      },
      child: ListTile(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => TransactionFormScreen(editing: t))),
        leading: CircleAvatar(
          backgroundColor: hexColor(t.categoryColor),
          child: Icon(categoryIcon(t.categoryIcon), color: Colors.white, size: 20),
        ),
        title: Text(t.description.isEmpty ? t.categoryName : t.description),
        subtitle: Text('${t.categoryName} · ${t.accountName}${t.isPaid ? '' : ' · pendente'}'),
        trailing: Text(
          '${isIncome ? '+' : '-'} ${money(t.amount)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: isIncome ? incomeColor : expenseColor),
        ),
      ),
    );
  }
}
