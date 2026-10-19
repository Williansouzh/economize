import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
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
    final amount = TextEditingController(text: inv.remaining.toStringAsFixed(2).replaceAll('.', ','));
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    final color = hexColor(account.color);
    final fg = onColor(color);
    final df = DateFormat("d 'de' MMM", 'pt_BR');

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
        actions: [
          IconButton(
            tooltip: 'Editar cartão',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showAccountSheet(context, editing: account),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Lançar'),
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
            children: [
              Card(
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(inv, -1)),
                    Expanded(
                      child: Text(
                        'Fatura de ${monthLabel(month)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(inv, 1)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: [color, Color.lerp(color, Colors.black, .3)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status,
                      style: TextStyle(color: fg.withValues(alpha: .85), fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      money(inv.total),
                      style: TextStyle(color: fg, fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vence em ${df.format(inv.dueDate)} · compras de ${df.format(inv.periodStart)} '
                      'a ${df.format(inv.closingDate.subtract(const Duration(days: 1)))}',
                      style: TextStyle(color: fg.withValues(alpha: .8), fontSize: 12),
                    ),
                    if (inv.paid > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Pago: ${money(inv.paid)}',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (account.creditLimit case final limit? when limit > 0) ...[
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: ((-account.balance) / limit).clamp(0, 1),
                          minHeight: 8,
                          color: fg,
                          backgroundColor: fg.withValues(alpha: .25),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Limite livre: ${money((limit + account.balance).clamp(0, limit))} de ${money(limit)}',
                        style: TextStyle(color: fg.withValues(alpha: .85), fontSize: 12),
                      ),
                    ],
                    if (!inv.isOpen && inv.remaining > 0) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: fg, foregroundColor: color),
                        onPressed: () => _pay(inv),
                        icon: const Icon(Icons.price_check),
                        label: Text('Pagar ${money(inv.remaining)}'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (inv.items.isEmpty)
                const EmptyState(
                  icon: Icons.credit_card,
                  title: 'Nenhuma compra nesta fatura',
                  message: 'Lance uma despesa escolhendo este cartão em "Pago com".',
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final (i, t) in inv.items.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        TransactionTile(t, showDate: true),
                      ],
                    ],
                  ),
                ),
              if (inv.isOpen) ...[
                const SizedBox(height: 12),
                Text(
                  'O botão de pagar aparece quando a fatura fecha.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
