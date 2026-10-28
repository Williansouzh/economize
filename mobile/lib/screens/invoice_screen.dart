import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'account_sheet.dart';
import 'transaction_form_screen.dart';
import 'transactions_screen.dart';

/// Fatura do cartão de crédito, mês a mês, com o botão de pagar (uma transferência para o cartão).
class InvoiceScreen extends StatefulWidget {
  final Account account;
  const InvoiceScreen({super.key, required this.account});
  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  /// Mês em que a fatura fecha (yyyy-MM). Nulo = a aberta hoje.
  String? _month;
  Future<Invoice>? _future;
  int _revision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.watch<AppState>().revision;
    if (revision != _revision) {
      _revision = revision;
      _load();
    }
  }

  void _load() => _future = context.read<AppState>().api.invoice(widget.account.id, month: _month);

  void _shift(Invoice current, int delta) {
    final m = DateTime.parse('${current.month}-01');
    setState(() {
      _month = DateFormat('yyyy-MM').format(DateTime(m.year, m.month + delta));
      _load();
    });
  }

  Future<void> _pay(Invoice inv) async {
    final state = context.read<AppState>();
    final banks = state.accounts.where((a) => !a.isCard).toList();
    if (banks.isEmpty) {
      showError(context, 'Crie uma conta (banco ou carteira) para pagar a fatura.');
      return;
    }
    var from = banks.first.id;
    final amount = TextEditingController(text: amountText(inv.remaining));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          icon: const Icon(Icons.price_check),
          title: const Text('Pagar fatura'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: from,
                decoration: const InputDecoration(labelText: 'Pagar com'),
                items: [for (final a in banks) DropdownMenuItem(value: a.id, child: Text(a.name))],
                onChanged: (v) => setLocal(() => from = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Pagar')),
          ],
        ),
      ),
    );
    final value = parseAmount(amount.text);
    if (ok != true || value == null || value <= 0) return;
    try {
      await state.api.saveTransfer(
        fromAccountId: from,
        toAccountId: widget.account.id,
        amount: value,
        // Pagamento conta para esta fatura se for feito depois do fechamento dela.
        date: DateTime.now().isBefore(inv.closingDate) ? inv.closingDate : DateTime.now(),
        description: 'Pagamento da fatura ${widget.account.name}',
        isPaid: true,
      );
      state.dataChanged();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final account = state.accounts.where((a) => a.id == widget.account.id).firstOrNull ?? widget.account;
    final cs = Theme.of(context).colorScheme;
    final df = DateFormat("d 'de' MMM", 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            tooltip: 'Editar cartão',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              // Cartão excluído: a fatura dele não tem mais o que mostrar.
              if (await showAccountSheet(context, editing: account) == true && context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: FutureBuilder<Invoice>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: () => setState(_load));
          final inv = snap.data;
          if (inv == null) return const Center(child: CircularProgressIndicator());
          final paid = inv.total > 0 && inv.paid >= inv.total;
          final status = inv.isOpen
              ? 'Aberta · fecha em ${df.format(inv.closingDate)}'
              : paid
              ? 'Paga'
              : 'Fechada · vence em ${df.format(inv.dueDate)}';
          final month = DateTime.parse('${inv.month}-01');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Row(
                children: [
                  IconButton(
                      tooltip: 'Fatura anterior', icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shift(inv, -1)),
                  Expanded(
                    child: Text('Fatura de ${monthLabel(month)}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                      tooltip: 'Próxima fatura', icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shift(inv, 1)),
                ],
              ),
              const SizedBox(height: 12),
              // Bloco da fatura (como no Nubank): fecha em / vence em e a ação de pagar sempre à vista.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(status, style: Theme.of(context).textTheme.bodySmall)),
                      if (paid) StatusBadge('paga', background: cs.primaryContainer, foreground: cs.onPrimaryContainer),
                    ]),
                    const SizedBox(height: 4),
                    Text(money(inv.total), style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: 4),
                    Text(
                      'Vence em ${df.format(inv.dueDate)} · compras de ${df.format(inv.periodStart)} '
                      'a ${df.format(inv.closingDate.subtract(const Duration(days: 1)))}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (inv.paid > 0) ...[
                      const SizedBox(height: 8),
                      Text('Pago: ${money(inv.paid)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                    if (account.creditLimit case final limit? when limit > 0) ...[
                      const SizedBox(height: 16),
                      StatusBar(
                        value: (-account.balance) / limit,
                        color: context.colors.forProgress((-account.balance) / limit),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Limite livre: ${money((limit + account.balance).clamp(0, limit))} de ${money(limit)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (!paid) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: !inv.isOpen && inv.remaining > 0 ? () => _pay(inv) : null,
                        icon: const Icon(Icons.price_check_rounded),
                        label: Text(inv.isOpen
                            ? 'Pagar fatura · fecha em ${df.format(inv.closingDate)}'
                            : 'Pagar ${money(inv.remaining)}'),
                      ),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 16),
              if (inv.items.isEmpty)
                const EmptyState(
                  icon: Icons.credit_card,
                  title: 'Nenhuma compra nesta fatura',
                  message: 'Lance uma despesa e escolha este cartão como forma de pagamento.',
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, t) in inv.items.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        TransactionTile(t, showDate: true, hideAccount: true),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
