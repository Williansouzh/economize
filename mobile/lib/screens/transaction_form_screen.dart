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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final categories = state.categories.where((c) => c.type == _type).toList();
    if (!categories.any((c) => c.id == _categoryId)) _categoryId = null;
    _accountId ??= state.accounts.isNotEmpty ? state.accounts.first.id : null;
    final color = _type == TxType.income ? incomeColor : expenseColor;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'Novo lançamento' : 'Editar lançamento'),
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<TxType>(
          segments: const [
            ButtonSegment(value: TxType.expense, label: Text('Despesa'), icon: Icon(Icons.arrow_downward)),
            ButtonSegment(value: TxType.income, label: Text('Receita'), icon: Icon(Icons.arrow_upward)),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          autofocus: widget.editing == null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
          decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
        ),
        const SizedBox(height: 12),
        TextField(controller: _description, decoration: const InputDecoration(labelText: 'Descrição')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _categoryId,
          key: ValueKey('cat-$_type'),
          decoration: const InputDecoration(labelText: 'Categoria'),
          items: categories
              .map((c) => DropdownMenuItem(
                    value: c.id,
                    child: Row(children: [
                      Icon(categoryIcon(c.icon), color: hexColor(c.color), size: 20),
                      const SizedBox(width: 8),
                      Text(c.name),
                    ]),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _accountId,
          decoration: const InputDecoration(labelText: 'Conta'),
          items: state.accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
          onChanged: (v) => setState(() => _accountId = v),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today),
          title: Text(DateFormat('dd/MM/yyyy').format(_date)),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              locale: const Locale('pt', 'BR'),
            );
            if (d != null) setState(() => _date = d);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_type == TxType.income ? 'Recebido' : 'Pago'),
          value: _isPaid,
          onChanged: (v) => setState(() => _isPaid = v),
        ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: _saving ? null : _save,
          child: const Padding(padding: EdgeInsets.all(14), child: Text('Salvar')),
        ),
      ]),
    );
  }
}
