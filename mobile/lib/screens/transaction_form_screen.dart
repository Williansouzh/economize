import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Converte "1.234,56" ou "1234.56" em double.
double? parseAmount(String text) {
  var s = text.trim().replaceAll('R\$', '').replaceAll(' ', '');
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s);
}

enum _Kind { expense, income, transfer }

const transferColor = Color(0xFF3B82F6);

/// Cria ou edita uma despesa, uma receita ou uma transferência entre contas.
class TransactionFormScreen extends StatefulWidget {
  final Transaction? editing;
  final Transfer? editingTransfer;
  const TransactionFormScreen({super.key, this.editing, this.editingTransfer});
  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  late final _tx = widget.editing;
  late final _tr = widget.editingTransfer;
  late _Kind _kind = _tr != null
      ? _Kind.transfer
      : (_tx?.type == TxType.income ? _Kind.income : _Kind.expense);
  late final _description = TextEditingController(text: _tx?.description ?? _tr?.description);
  late final _amount = TextEditingController(
      text: (_tx?.amount ?? _tr?.amount)?.toStringAsFixed(2).replaceAll('.', ','));
  late DateTime _date = _tx?.date ?? _tr?.date ?? DateTime.now();
  late bool _isPaid = _tx?.isPaid ?? _tr?.isPaid ?? true;
  late String? _accountId = _tx?.accountId ?? _tr?.fromAccountId;
  late String? _toAccountId = _tr?.toAccountId;
  late String? _categoryId = _tx?.categoryId;
  bool _saving = false;

  bool get _isEditing => _tx != null || _tr != null;
  TxType get _type => _kind == _Kind.income ? TxType.income : TxType.expense;

  Future<void> _save() async {
    final state = context.read<AppState>();
    final amount = parseAmount(_amount.text);
    final transfer = _kind == _Kind.transfer;
    if (amount == null || amount <= 0 || _accountId == null ||
        (transfer ? _toAccountId == null : _categoryId == null)) {
      showError(context, transfer ? 'Preencha valor, conta de origem e de destino.' : 'Preencha valor, conta e categoria.');
      return;
    }
    if (transfer && _accountId == _toAccountId) {
      showError(context, 'Escolha contas de origem e destino diferentes.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (transfer) {
        await state.api.saveTransfer(
          id: _tr?.id,
          fromAccountId: _accountId!,
          toAccountId: _toAccountId!,
          amount: amount,
          date: _date,
          description: _description.text,
          isPaid: _isPaid,
        );
      } else {
        await state.api.saveTransaction(
          id: _tx?.id,
          accountId: _accountId!,
          categoryId: _categoryId!,
          description: _description.text,
          amount: amount,
          type: _type,
          date: _date,
          isPaid: _isPaid,
        );
      }
      state.dataChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (d != null) setState(() => _date = d);
  }

  Widget _accountChips(List<Account> accounts, String? selected, ValueChanged<String> onTap, {String? exclude}) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in accounts)
          if (a.id != exclude)
            _OptionChip(
              icon: accountIcon(a.icon),
              label: a.name,
              color: hexColor(a.color),
              selected: a.id == selected,
              onTap: () => onTap(a.id),
            ),
      ]);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final transfer = _kind == _Kind.transfer;
    final categories = state.categories.where((c) => c.type == _type).toList();
    if (!categories.any((c) => c.id == _categoryId)) _categoryId = null;
    _accountId ??= state.accounts.isNotEmpty ? state.accounts.first.id : null;
    if (transfer && _toAccountId == _accountId) _toAccountId = null;
    final color = switch (_kind) {
      _Kind.income => incomeColor,
      _Kind.expense => expenseColor,
      _Kind.transfer => transferColor,
    };
    final text = Theme.of(context).textTheme;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(_date.year, _date.month, _date.day);

    return Scaffold(
      appBar: AppBar(
        title: Text(switch ((_isEditing, transfer)) {
          (false, false) => 'Novo lançamento',
          (true, false) => 'Editar lançamento',
          (false, true) => 'Nova transferência',
          (true, true) => 'Editar transferência',
        }),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        SegmentedButton<_Kind>(
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: color.withValues(alpha: .15),
            selectedForegroundColor: color,
          ),
          segments: [
            // Lançamento e transferência ficam em lugares diferentes: na edição não dá para trocar entre eles.
            ButtonSegment(
                value: _Kind.expense, label: const Text('Despesa'), icon: const Icon(Icons.north_east),
                enabled: _tr == null),
            ButtonSegment(
                value: _Kind.income, label: const Text('Receita'), icon: const Icon(Icons.south_west),
                enabled: _tr == null),
            ButtonSegment(
                value: _Kind.transfer, label: const Text('Transferir'), icon: const Icon(Icons.swap_horiz),
                enabled: _tx == null),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 16),
        // Valor em destaque, na cor do tipo.
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(switch (_kind) {
              _Kind.income => 'Quanto você recebeu?',
              _Kind.expense => 'Quanto você gastou?',
              _Kind.transfer => 'Quanto você vai mover?',
            }, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            TextField(
              controller: _amount,
              autofocus: !_isEditing,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: color),
              decoration: InputDecoration(
                prefixText: 'R\$ ',
                prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color),
                hintText: '0,00',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _description,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: transfer ? 'Descrição (opcional)' : 'Descrição',
            prefixIcon: const Icon(Icons.notes),
          ),
        ),
        const SizedBox(height: 20),
        if (transfer) ...[
          Text('Sai de', style: text.labelLarge),
          const SizedBox(height: 8),
          _accountChips(state.accounts, _accountId, (id) => setState(() => _accountId = id)),
          const SizedBox(height: 20),
          Text('Vai para', style: text.labelLarge),
          const SizedBox(height: 8),
          if (state.accounts.length < 2)
            Text('Crie outra conta na tela inicial para transferir entre elas.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
          else
            _accountChips(state.accounts, _toAccountId, (id) => setState(() => _toAccountId = id),
                exclude: _accountId),
        ] else ...[
          Text('Categoria', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in categories)
              _OptionChip(
                icon: categoryIcon(c.icon),
                label: c.name,
                color: hexColor(c.color),
                selected: c.id == _categoryId,
                onTap: () => setState(() => _categoryId = c.id),
              ),
          ]),
          const SizedBox(height: 20),
          Text(_kind == _Kind.income ? 'Recebido em' : 'Pago com', style: text.labelLarge),
          const SizedBox(height: 8),
          _accountChips(state.accounts, _accountId, (id) => setState(() => _accountId = id)),
        ],
        const SizedBox(height: 20),
        Text('Data', style: text.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            label: const Text('Hoje'),
            selected: day == today,
            onSelected: (_) => setState(() => _date = today),
          ),
          ChoiceChip(
            label: const Text('Ontem'),
            selected: day == yesterday,
            onSelected: (_) => setState(() => _date = yesterday),
          ),
          ChoiceChip(
            avatar: const Icon(Icons.calendar_today, size: 16),
            label: Text(day == today || day == yesterday ? 'Outra data' : DateFormat('dd/MM/yyyy').format(_date)),
            selected: day != today && day != yesterday,
            onSelected: (_) => _pickDate(),
          ),
        ]),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            secondary: IconBadge(_isPaid ? Icons.check_circle : Icons.schedule,
                _isPaid ? incomeColor : warningColor, size: 38),
            title: Text(switch (_kind) {
              _Kind.income => 'Já recebi',
              _Kind.expense => 'Já paguei',
              _Kind.transfer => 'Já transferi',
            }),
            subtitle: Text(_isPaid ? 'Entra no saldo atual' : 'Fica como pendente e entra no previsto'),
            value: _isPaid,
            onChanged: (v) => setState(() => _isPaid = v),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('Salvar'),
        ),
      ]),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _OptionChip(
      {required this.icon, required this.label, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .14) : Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : cs.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconBadge(icon, color, size: 28, solid: selected),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}
