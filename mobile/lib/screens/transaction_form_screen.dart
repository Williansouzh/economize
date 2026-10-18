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

class TransactionFormScreen extends StatefulWidget {
  final Transaction? editing;
  const TransactionFormScreen({super.key, this.editing});
  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  late TxType _type = widget.editing?.type ?? TxType.expense;
  late final _description = TextEditingController(text: widget.editing?.description);
  late final _amount = TextEditingController(
      text: widget.editing?.amount.toStringAsFixed(2).replaceAll('.', ','));
  late DateTime _date = widget.editing?.date ?? DateTime.now();
  late bool _isPaid = widget.editing?.isPaid ?? true;
  late String? _accountId = widget.editing?.accountId;
  late String? _categoryId = widget.editing?.categoryId;
  bool _saving = false;

  Future<void> _save() async {
    final state = context.read<AppState>();
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0 || _accountId == null || _categoryId == null) {
      showError(context, 'Preencha valor, conta e categoria.');
      return;
    }
    setState(() => _saving = true);
    try {
      await state.api.saveTransaction(
        id: widget.editing?.id,
        accountId: _accountId!,
        categoryId: _categoryId!,
        description: _description.text,
        amount: amount,
        type: _type,
        date: _date,
        isPaid: _isPaid,
      );
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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final categories = state.categories.where((c) => c.type == _type).toList();
    if (!categories.any((c) => c.id == _categoryId)) _categoryId = null;
    _accountId ??= state.accounts.isNotEmpty ? state.accounts.first.id : null;
    final isIncome = _type == TxType.income;
    final color = isIncome ? incomeColor : expenseColor;
    final text = Theme.of(context).textTheme;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final day = DateTime(_date.year, _date.month, _date.day);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'Novo lançamento' : 'Editar lançamento'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        SegmentedButton<TxType>(
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: color.withValues(alpha: .15),
            selectedForegroundColor: color,
          ),
          segments: const [
            ButtonSegment(value: TxType.expense, label: Text('Despesa'), icon: Icon(Icons.north_east)),
            ButtonSegment(value: TxType.income, label: Text('Receita'), icon: Icon(Icons.south_west)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
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
            Text(isIncome ? 'Quanto você recebeu?' : 'Quanto você gastou?',
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            TextField(
              controller: _amount,
              autofocus: widget.editing == null,
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
          decoration: const InputDecoration(
            labelText: 'Descrição',
            prefixIcon: Icon(Icons.notes),
          ),
        ),
        const SizedBox(height: 20),
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
        Text(isIncome ? 'Recebido em' : 'Pago com', style: text.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in state.accounts)
            _OptionChip(
              icon: accountIcon(a.icon),
              label: a.name,
              color: hexColor(a.color),
              selected: a.id == _accountId,
              onTap: () => setState(() => _accountId = a.id),
            ),
        ]),
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
            title: Text(isIncome ? 'Já recebi' : 'Já paguei'),
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
