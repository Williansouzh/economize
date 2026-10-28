import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'transaction_form_screen.dart';

/// Cria ou edita uma conta ou um cartão de crédito: nome, saldo inicial (ou limite, fechamento e
/// vencimento), ícone e cor, com prévia ao vivo. Devolve true se a conta foi excluída.
Future<bool?> showAccountSheet(BuildContext context, {Account? editing, bool card = false}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // A barra de navegação do Android fica por cima da folha; SafeArea reserva o espaço dela.
  builder: (_) => SafeArea(top: false, child: _AccountSheet(editing: editing, card: card)),
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
  /// Editando uma conta comum, o campo é o saldo de hoje: quem importa só alguns meses de extrato
  /// não sabe o saldo de antes do primeiro dia, mas sabe o que o banco mostra agora.
  bool get _tracksBalance => widget.editing != null && !widget.editing!.isCard;

  late final _balance = TextEditingController(
    text: amountText(_tracksBalance ? widget.editing!.balance : widget.editing?.initialBalance ?? 0),
  );
  late String _icon = widget.editing?.icon ?? (widget.card ? 'credit_card' : 'account_balance');
  late String _color = widget.editing?.color ?? accountColors[3];
  late bool _isCard = widget.editing?.isCard ?? widget.card;
  late final _limit = TextEditingController(text: widget.editing?.creditLimit == null ? null : amountText(widget.editing!.creditLimit!));
  late int _closingDay = widget.editing?.closingDay ?? 1;
  late int _dueDay = widget.editing?.dueDay ?? 10;
  bool _saving = false;

  double _initialBalance() {
    final typed = parseAmount(_balance.text) ?? 0;
    // Cartão começa zerado: o que importa é a fatura, que vem dos lançamentos.
    if (_isCard) return widget.editing?.initialBalance ?? 0;
    if (!_tracksBalance) return typed;
    // Saldo atual = inicial + lançamentos; muda o inicial para o atual bater com o digitado.
    final e = widget.editing!;
    return e.initialBalance + typed - e.balance;
  }

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
        initialBalance: _initialBalance(),
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
        icon: Icon(Icons.delete_outline_rounded, color: c.colors.expense),
        title: Text('Excluir "${widget.editing!.name}"?'),
        content: Text('Todos os lançamentos e transferências d$what também serão apagados. '
            'Isso não pode ser desfeito.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.colors.expense, foregroundColor: Colors.white),
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
    final color = tintOf(context, _color);
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
            }, style: text.titleLarge),
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
            // Prévia de como a conta aparece no Início.
            Card(
              child: ListTile(
                minTileHeight: 64,
                leading: IconBadge(accountIcon(_icon), color),
                title: ValueListenableBuilder(
                  valueListenable: _name,
                  builder: (_, v, _) => Text(v.text.isEmpty ? 'Nome da conta' : v.text),
                ),
                subtitle: Text(_isCard ? 'Cartão de crédito' : 'Conta'),
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
              Text('Compras a partir do dia do fechamento entram na fatura seguinte.', style: text.bodySmall),
            ] else
              TextField(
                controller: _balance,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                inputFormatters: [MoneyInputFormatter(signed: true)],
                decoration: InputDecoration(
                  labelText: _tracksBalance ? 'Saldo atual' : 'Saldo inicial',
                  helperText: _tracksBalance ? 'O mesmo valor que aparece hoje no app do banco.' : null,
                  prefixText: 'R\$ ',
                ),
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
            PaletteColorPicker(selected: _color, onChanged: (c) => setState(() => _color = c)),
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
                style: TextButton.styleFrom(foregroundColor: context.colors.expense),
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
