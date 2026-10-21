import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'transaction_form_screen.dart';

/// Cria ou edita uma conta ou um cartão de crédito: nome, saldo inicial (ou limite, fechamento e
/// vencimento), ícone e cor, com prévia ao vivo. Devolve true se a conta foi excluída.
Future<bool?> showAccountSheet(BuildContext context, {Account? editing, bool card = false}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _AccountSheet(editing: editing, card: card),
);

class _AccountSheet extends StatefulWidget {
  final Account? editing;
  final bool card;
  const _AccountSheet({this.editing, this.card = false});
  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final _name = TextEditingController(text: widget.editing?.name);
  late final _balance = TextEditingController(
    text: amountText(widget.editing?.initialBalance ?? 0),
  );
  late String _icon = widget.editing?.icon ?? (widget.card ? 'credit_card' : 'account_balance');
  late String _color = widget.editing?.color ?? accountColors.first;
  late bool _isCard = widget.editing?.isCard ?? widget.card;
  late final _limit = TextEditingController(text: widget.editing?.creditLimit == null ? null : amountText(widget.editing!.creditLimit!));
  late int _closingDay = widget.editing?.closingDay ?? 1;
  late int _dueDay = widget.editing?.dueDay ?? 10;
  bool _saving = false;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showError(context, 'Dê um nome para a conta.');
      return;
    }
    final state = context.read<AppState>();
    setState(() => _saving = true);
    try {
      await state.api.saveAccount(
        id: widget.editing?.id,
        name: name,
        // Cartão começa zerado: o que importa é a fatura, que vem dos lançamentos.
        initialBalance: _isCard ? (widget.editing?.initialBalance ?? 0) : parseAmount(_balance.text) ?? 0,
        color: _color,
        icon: _icon,
        isCard: _isCard,
        creditLimit: _isCard ? parseAmount(_limit.text) : null,
        closingDay: _closingDay,
        dueDay: _dueDay,
      );
      state.dataChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    final what = _isCard ? 'o cartão' : 'a conta';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: expenseColor),
        title: Text('Excluir "${widget.editing!.name}"?'),
        content: Text('Todos os lançamentos e transferências d$what também serão apagados. '
            'Isso não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: expenseColor),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await state.api.deleteWalletAccount(widget.editing!.id);
      state.dataChanged();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = hexColor(_color);
    final fg = onColor(color);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(switch ((widget.editing == null, _isCard)) {
              (true, false) => 'Nova conta',
              (true, true) => 'Novo cartão de crédito',
              (false, false) => 'Editar conta',
              (false, true) => 'Editar cartão',
            }, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Conta'), icon: Icon(Icons.account_balance_outlined)),
                ButtonSegment(value: true, label: Text('Cartão de crédito'), icon: Icon(Icons.credit_card)),
              ],
              selected: {_isCard},
              onSelectionChanged: (s) => setState(() {
                _isCard = s.first;
                if (_isCard && _icon == 'account_balance') _icon = 'credit_card';
                if (!_isCard && _icon == 'credit_card') _icon = 'account_balance';
              }),
            ),
            const SizedBox(height: 16),
            // Prévia de como a conta aparece na tela inicial.
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [color, Color.lerp(color, Colors.black, .25)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Icon(accountIcon(_icon), color: fg, size: 32),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: _name,
                      builder: (_, v, _) => Text(
                        v.text.isEmpty ? 'Nome da conta' : v.text,
                        style: text.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Nubank, Itaú, Carteira'),
            ),
            const SizedBox(height: 12),
            if (_isCard) ...[
              TextField(
                controller: _limit,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyInputFormatter()],
                decoration: const InputDecoration(labelText: 'Limite (opcional)', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DayField(
                      label: 'Fecha no dia',
                      value: _closingDay,
                      onChanged: (d) => setState(() => _closingDay = d),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DayField(
                      label: 'Vence no dia',
                      value: _dueDay,
                      onChanged: (d) => setState(() => _dueDay = d),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Compras a partir do dia do fechamento entram na fatura seguinte.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ] else
              TextField(
                controller: _balance,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                inputFormatters: [MoneyInputFormatter(signed: true)],
                decoration: const InputDecoration(labelText: 'Saldo inicial', prefixText: 'R\$ '),
              ),
            const SizedBox(height: 20),
            Text('Ícone', style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in accountIcons.entries)
                  _Pickable(
                    selected: e.key == _icon,
                    color: color,
                    onTap: () => setState(() => _icon = e.key),
                    child: Icon(e.value, color: e.key == _icon ? color : null),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Cor', style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in accountColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: hexColor(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: c == _color ? Icon(Icons.check, color: onColor(hexColor(c)), size: 20) : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.editing != null ? 'Salvar' : (_isCard ? 'Criar cartão' : 'Criar conta')),
            ),
            if (widget.editing != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: expenseColor),
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: Text(_isCard ? 'Excluir cartão' : 'Excluir conta'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pickable extends StatelessWidget {
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  const _Pickable({required this.selected, required this.color, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: .14) : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? color : Colors.transparent, width: 2),
      ),
      child: child,
    ),
  );
}

class _DayField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  const _DayField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d'))],
    onChanged: (d) => onChanged(d!),
  );
}
