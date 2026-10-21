import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'transaction_form_screen.dart';

const _goalIcons = <String, IconData>{
  'savings': Icons.savings,
  'flight': Icons.flight,
  'home': Icons.home,
  'directions_car': Icons.directions_car,
  'school': Icons.school,
  'health_and_safety': Icons.health_and_safety,
  'celebration': Icons.celebration,
  'devices': Icons.devices,
  'child_friendly': Icons.child_friendly,
  'pets': Icons.pets,
  'beach_access': Icons.beach_access,
  'emoji_events': Icons.emoji_events,
};
IconData goalIcon(String name) => _goalIcons[name] ?? Icons.savings;

/// Metas de economia: quanto falta, prazo e quanto guardar por mês.
class GoalsSection extends StatelessWidget {
  const GoalsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Metas', style: Theme.of(context).textTheme.titleLarge)),
            TextButton.icon(
              onPressed: () => showGoalSheet(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nova meta'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Goal>>(
          // revision no key: depois de salvar, busca de novo.
          key: ValueKey(state.revision),
          future: state.goals(),
          builder: (context, snap) {
            if (snap.hasError) return ErrorView(error: snap.error!, onRetry: state.dataChanged);
            final goals = snap.data;
            if (goals == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (goals.isEmpty) {
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => showGoalSheet(context),
                  child: const EmptyState(
                    icon: Icons.flag_outlined,
                    title: 'Qual é o seu próximo sonho?',
                    message: 'Crie uma meta, como "Viagem de férias: R\$ 5.000 até dezembro", e acompanhe quanto já guardou.',
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (final g in goals) ...[_GoalCard(g), const SizedBox(height: 12)],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal g;
  const _GoalCard(this.g);

  @override
  Widget build(BuildContext context) {
    final color = hexColor(g.color);
    final cs = Theme.of(context).colorScheme;
    final hint = g.reached
        ? 'Meta batida! 🎉'
        : g.monthlyNeeded != null
        ? 'Guarde ${money(g.monthlyNeeded!)} por mês até ${DateFormat('MMM/yy', 'pt_BR').format(g.deadline!)}'
        : 'Faltam ${money(g.target - g.saved)}';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showGoalSheet(context, editing: g),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(goalIcon(g.icon), color, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(
                          '${money(g.saved)} de ${money(g.target)}',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(g.progress * 100).round()}%',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: g.progress,
                  minHeight: 10,
                  color: color,
                  backgroundColor: color.withValues(alpha: .14),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(hint, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _deposit(context, g),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Guardar ou retirar dinheiro da meta.
Future<void> _deposit(BuildContext context, Goal g) async {
  final state = context.read<AppState>();
  final amount = TextEditingController();
  var withdraw = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setLocal) => AlertDialog(
        title: Text(g.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Guardar')),
                ButtonSegment(value: true, label: Text('Retirar')),
              ],
              selected: {withdraw},
              onSelectionChanged: (s) => setLocal(() => withdraw = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '),
            ),
            const SizedBox(height: 8),
            Text(
              'Isso só registra a meta: não mexe no saldo das suas contas.',
              style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
        ],
      ),
    ),
  );
  final value = parseAmount(amount.text);
  if (ok != true || value == null || value <= 0) return;
  try {
    final updated = await state.api.depositGoal(g.id, withdraw ? -value : value);
    state.dataChanged();
    if (updated.reached && !g.reached && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('🎉 Parabéns! Você completou a meta "${g.name}"!')));
    }
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Cria ou edita uma meta.
Future<void> showGoalSheet(BuildContext context, {Goal? editing}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _GoalSheet(editing: editing),
);

class _GoalSheet extends StatefulWidget {
  final Goal? editing;
  const _GoalSheet({this.editing});
  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late final _name = TextEditingController(text: widget.editing?.name);
  late final _target = TextEditingController(text: widget.editing == null ? null : amountText(widget.editing!.target));
  late DateTime? _deadline = widget.editing?.deadline;
  late String _icon = widget.editing?.icon ?? 'savings';
  late String _color = widget.editing?.color ?? categoryColors.first;
  bool _saving = false;

  Future<void> _save() async {
    final target = parseAmount(_target.text);
    if (_name.text.trim().isEmpty || target == null || target <= 0) {
      showError(context, 'Dê um nome e diga quanto quer juntar.');
      return;
    }
    final state = context.read<AppState>();
    setState(() => _saving = true);
    try {
      await state.api.saveGoal(
        id: widget.editing?.id,
        name: _name.text.trim(),
        target: target,
        deadline: _deadline,
        icon: _icon,
        color: _color,
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Excluir "${widget.editing!.name}"?'),
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
    try {
      await state.api.deleteGoal(widget.editing!.id);
      state.dataChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = hexColor(_color);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.editing == null ? 'Nova meta' : 'Editar meta', style: text.titleLarge)),
                if (widget.editing != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: expenseColor),
                    onPressed: _delete,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Viagem, reserva de emergência'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              decoration: const InputDecoration(labelText: 'Quanto quer juntar', prefixText: 'R\$ '),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(
                _deadline == null ? 'Definir prazo (opcional)' : 'Até ${DateFormat('dd/MM/yyyy').format(_deadline!)}',
              ),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _deadline ?? DateTime(now.year, now.month + 6, now.day),
                  firstDate: now,
                  lastDate: DateTime(now.year + 30),
                );
                if (d != null) setState(() => _deadline = d);
              },
            ),
            if (_deadline != null)
              TextButton(onPressed: () => setState(() => _deadline = null), child: const Text('Sem prazo')),
            const SizedBox(height: 16),
            Text('Ícone', style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _goalIcons.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _icon = e.key),
                    child: IconBadge(e.value, e.key == _icon ? color : Colors.grey, size: 46, solid: e.key == _icon),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Cor', style: text.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in categoryColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: hexColor(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.editing == null ? 'Criar meta' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
