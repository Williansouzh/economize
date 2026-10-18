import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/month_loader.dart';
import 'dashboard_screen.dart';
import 'transaction_form_screen.dart';

/// Limites de gasto mensais por categoria.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  Future<void> _edit(BuildContext context, {Budget? budget}) async {
    final state = context.read<AppState>();
    final expenseCats = state.categories.where((c) => c.type == TxType.expense).toList();
    String? categoryId = budget?.categoryId;
    final limit = TextEditingController(text: budget?.limit.toStringAsFixed(2).replaceAll('.', ','));
    var recurring = budget?.recurring ?? true;
    final inherited = budget?.inherited ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, setDialog) => AlertDialog(
        title: Text(budget == null ? 'Novo orçamento' : 'Editar orçamento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (inherited)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Este limite vem de ${monthLabel(DateTime.parse('${budget!.month}-01'))} e se repete todo mês. '
                'Salvar aqui muda a partir de ${monthLabel(state.month)}.',
                style: TextStyle(fontSize: 13, color: Theme.of(c).colorScheme.onSurfaceVariant),
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: categoryId,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: expenseCats
                .map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Row(children: [
                        Icon(categoryIcon(c.icon), color: hexColor(c.color), size: 20),
                        const SizedBox(width: 8),
                        Text(c.name),
                      ]),
                    ))
                .toList(),
            onChanged: budget == null ? (v) => categoryId = v : null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Limite mensal', prefixText: 'R\$ '),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.repeat),
            title: const Text('Repetir todo mês'),
            subtitle: Text(recurring ? 'Vale também para os próximos meses' : 'Só para ${monthLabel(state.month)}'),
            value: recurring,
            onChanged: (v) => setDialog(() => recurring = v),
          ),
        ]),
        actions: [
          if (budget != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: expenseColor),
              onPressed: () async {
                try {
                  await state.api.deleteBudget(budget.id, state.monthKey);
                  if (c.mounted) Navigator.pop(c, true);
                } catch (e) {
                  if (c.mounted) showError(c, e);
                }
              },
              child: Text(inherited ? 'Parar de repetir' : 'Excluir'),
            ),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final value = parseAmount(limit.text);
              if (categoryId == null || value == null || value <= 0) return;
              try {
                await state.api.saveBudget(categoryId!, state.monthKey, value, recurring: recurring);
                if (c.mounted) Navigator.pop(c, true);
              } catch (e) {
                if (c.mounted) showError(c, e);
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      )),
    );
    if (ok == true) state.dataChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const MonthSelector(),
      Expanded(
        child: MonthLoader<Dashboard>(
          load: (s) => s.api.dashboard(s.monthKey),
          builder: (context, d, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            if (d.budgets.isEmpty)
              const EmptyState(
                icon: Icons.savings_outlined,
                title: 'Nenhum orçamento ainda',
                message: 'Defina limites de gasto por categoria e acompanhe ao longo do mês.',
              )
            else ...[
              _BudgetsSummary(d.budgets),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(children: [
                    for (final b in d.budgets) BudgetProgress(b, onTap: () => _edit(context, budget: b)),
                  ]),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Toque em um orçamento para editar.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar orçamento'),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _BudgetsSummary extends StatelessWidget {
  final List<Budget> budgets;
  const _BudgetsSummary(this.budgets);

  @override
  Widget build(BuildContext context) {
    final limit = budgets.fold(0.0, (a, b) => a + b.limit);
    final spent = budgets.fold(0.0, (a, b) => a + b.spent);
    final over = budgets.where((b) => b.spent > b.limit).length;
    final progress = limit == 0 ? 0.0 : spent / limit;
    final color = progress > 1 ? expenseColor : (progress > .8 ? warningColor : incomeColor);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(fit: StackFit.expand, children: [
              CircularProgressIndicator(
                value: progress.clamp(0, 1),
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: color.withValues(alpha: .14),
              ),
              Center(
                child: Text('${(progress * 100).round()}%',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Orçamento do mês', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('${money(spent)} de ${money(limit)}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              const SizedBox(height: 6),
              Text(
                over == 0
                    ? 'Restam ${money((limit - spent).clamp(0, double.infinity))} para gastar'
                    : over == 1
                        ? '1 categoria estourou o limite'
                        : '$over categorias estouraram o limite',
                style: TextStyle(color: over == 0 ? incomeColor : expenseColor, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
