import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'transaction_form_screen.dart';

/// Cria ou edita uma conta: nome, saldo inicial, ícone e cor, com prévia ao vivo.
Future<void> showAccountSheet(BuildContext context, {Account? editing}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AccountSheet(editing: editing),
    );

class _AccountSheet extends StatefulWidget {
  final Account? editing;
  const _AccountSheet({this.editing});
  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final _name = TextEditingController(text: widget.editing?.name);
  late final _balance = TextEditingController(
      text: (widget.editing?.initialBalance ?? 0).toStringAsFixed(2).replaceAll('.', ','));
  late String _icon = widget.editing?.icon ?? 'account_balance';
  late String _color = widget.editing?.color ?? accountColors.first;
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
        initialBalance: parseAmount(_balance.text) ?? 0,
        color: _color,
        icon: _icon,
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
    final color = hexColor(_color);
    final fg = onColor(color);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.editing == null ? 'Nova conta' : 'Editar conta',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
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
            child: Row(children: [
              Icon(accountIcon(_icon), color: fg, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: _name,
                  builder: (_, v, _) => Text(v.text.isEmpty ? 'Nome da conta' : v.text,
                      style: text.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Nubank, Itaú, Carteira'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _balance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'Saldo inicial', prefixText: 'R\$ '),
          ),
          const SizedBox(height: 20),
          Text('Ícone', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final e in accountIcons.entries)
              _Pickable(
                selected: e.key == _icon,
                color: color,
                onTap: () => setState(() => _icon = e.key),
                child: Icon(e.value, color: e.key == _icon ? color : null),
              ),
          ]),
          const SizedBox(height: 20),
          Text('Cor', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
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
                        width: 3),
                  ),
                  child: c == _color ? Icon(Icons.check, color: onColor(hexColor(c)), size: 20) : null,
                ),
              ),
          ]),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.editing == null ? 'Criar conta' : 'Salvar'),
          ),
        ]),
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
