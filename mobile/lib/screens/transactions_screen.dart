import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/month_loader.dart';
import 'transaction_form_screen.dart';

class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const MonthSelector(),
        Expanded(
          child: MonthLoader<(List<Transaction>, List<Transfer>)>(
            load: (s) => s.monthEntries(),
            builder: (context, data, _) {
              final (txs, transfers) = data;
              if (txs.isEmpty && transfers.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 60),
                    EmptyState(
                      icon: Icons.receipt_long,
                      mascot: true,
                      title: 'Nenhum lançamento neste mês',
                      message: 'Toque em Lançar, no meio da barra de baixo, para registrar uma receita ou despesa.',
                    ),
                  ],
                );
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
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  _MonthSummary(income: income, expenses: expenses),
                  for (final day in days) ...[
                    _DayHeader(day, sum(byDay[day]!, TxType.income) - sum(byDay[day]!, TxType.expense)),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final (i, item) in byDay[day]!.indexed) ...[
                            if (i > 0) const Divider(height: 1, indent: 72),
                            switch (item) {
                              Transaction t => TransactionTile(t),
                              Transfer t => _TransferTile(t),
                              _ => const SizedBox.shrink(),
                            },
                          ],
                        ],
                      ),
                    ),
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

/// Entrou · Saiu · Resultado do mês (Resultado, não "Saldo": saldo é o dinheiro nas contas).
class _MonthSummary extends StatelessWidget {
  final double income, expenses;
  const _MonthSummary({required this.income, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final colors = context.colors;
    Widget item(String label, String value, Color color) => Expanded(
          child: Column(children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 2),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: valueStyle.copyWith(color: color))),
          ]),
        );
    Widget divider() => Container(width: 1, height: 32, color: cs.outlineVariant);
    final result = income - expenses;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Row(
          children: [
            item('Entrou', '+ ${money(income)}', colors.income),
            divider(),
            item('Saiu', '− ${money(expenses)}', cs.onSurface),
            divider(),
            item('Resultado', '${result < 0 ? '−' : '+'} ${money(result.abs())}', result < 0 ? colors.expense : cs.onSurface),
          ],
        ),
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
    final style = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(label[0].toUpperCase() + label.substring(1), style: style)),
          Text('${total >= 0 ? '+' : '−'} ${money(total.abs())}', style: style),
        ],
      ),
    );
  }
}

/// Linha de um lançamento: valor à direita em 16/800; despesa em tinta com "−", receita na cor de
/// receita com "+" (só o que entra ganha cor). Toque edita; arrastar para a esquerda exclui e para a
/// direita lança de novo. Usada também na busca e na fatura.
class TransactionTile extends StatelessWidget {
  final Transaction t;

  /// Mostra a data no lugar do agrupamento por dia (busca e fatura).
  final bool showDate;

  /// Esconde a conta (na fatura, todas são do mesmo cartão).
  final bool hideAccount;
  const TransactionTile(this.t, {super.key, this.showDate = false, this.hideAccount = false});

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == TxType.income;
    final cs = Theme.of(context).colorScheme;
    final colors = context.colors;
    final meta = [
      if (showDate) DateFormat('dd/MM/yy').format(t.date),
      t.categoryName,
      if (!hideAccount) t.accountName,
    ].join(' · ');
    return _Deletable(
      id: t.id,
      title: 'Excluir lançamento?',
      content: t.description.isEmpty ? t.categoryName : t.description,
      series: t.inSeries,
      onDelete: (api, future) => api.deleteTransaction(t.id, future: future),
      onRepeat: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionFormScreen(duplicate: t))),
      child: ListTile(
        minTileHeight: 64,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionFormScreen(editing: t))),
        leading: IconBadge(categoryIcon(t.categoryIcon), tintOf(context, t.categoryColor)),
        title: Text(t.description.isEmpty ? t.categoryName : t.description, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(children: [
          Flexible(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (t.installmentCount case final n?) ...[
            const SizedBox(width: 6),
            Text('${t.installmentNumber}/$n', style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface)),
          ] else if (t.inSeries) ...[
            const SizedBox(width: 6),
            Icon(Icons.repeat_rounded, size: 14, color: cs.onSurfaceVariant, semanticLabel: 'fixo'),
          ],
        ]),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${isIncome ? '+' : '−'} ${money(t.amount)}',
                style: valueStyle.copyWith(color: isIncome ? colors.income : cs.onSurface)),
            if (!t.isPaid) ...[const SizedBox(height: 4), const _PendingBadge()],
          ],
        ),
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
      onDelete: (api, _) => api.deleteTransfer(t.id),
      child: ListTile(
        minTileHeight: 64,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionFormScreen(editingTransfer: t))),
        leading: IconBadge(Icons.swap_horiz_rounded, context.colors.info),
        title: Text(
          t.description.isEmpty ? 'Transferência' : t.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('${t.fromAccountName} → ${t.toAccountName}', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(t.amount), style: valueStyle.copyWith(color: cs.onSurfaceVariant)),
            if (!t.isPaid) ...[const SizedBox(height: 4), const _PendingBadge()],
          ],
        ),
      ),
    );
  }
}

/// Pendente: ícone de relógio + texto escuro sobre âmbar claro (6,8:1), não só cor.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) => StatusBadge.warning(context, 'pendente', icon: Icons.schedule_rounded);
}

/// Arrastar para a esquerda pede confirmação e exclui. Em série (fixo ou parcelado), pergunta se
/// exclui só este ou também os próximos. Com [onRepeat], arrastar para a direita lança de novo.
class _Deletable extends StatelessWidget {
  final String id, title, content;
  final bool series;
  final Future<void> Function(ApiClient api, bool future) onDelete;
  final VoidCallback? onRepeat;
  final Widget child;
  const _Deletable({
    required this.id,
    required this.title,
    required this.content,
    required this.onDelete,
    required this.child,
    this.onRepeat,
    this.series = false,
  });

  @override
  Widget build(BuildContext context) {
    var future = false;
    final colors = context.colors;
    final cs = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(id),
      direction: onRepeat == null ? DismissDirection.endToStart : DismissDirection.horizontal,
      background: Container(
        color: cs.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.replay_rounded, color: cs.onPrimaryContainer),
          const SizedBox(width: 8),
          Text('Lançar de novo', style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800)),
        ]),
      ),
      secondaryBackground: Container(
        color: colors.expense,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Excluir', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onRepeat?.call();
          return false;
        }
        if (series) {
          final choice = await askSeriesScope(context, editing: false);
          future = choice ?? false;
          return choice != null;
        }
        return showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: Icon(Icons.delete_outline_rounded, color: colors.expense),
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: colors.expense, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) async {
        final state = context.read<AppState>();
        try {
          await onDelete(state.api, future);
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
        state.dataChanged();
      },
      child: child,
    );
  }
}
