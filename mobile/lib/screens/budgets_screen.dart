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
    var recurring = budget?.isRecurring ?? true;
    final limit = TextEditingController(text: budget?.limit.toStringAsFixed(2).replaceAll('.', ','));
    final month = monthLabel(state.month);

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          title: Text(budget == null
              ? 'Novo orçamento'
              : budget.inherited
                  ? 'Alterar a partir de $month'
                  : 'Editar orçamento'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: 'Categoria'),
              items: expenseCats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: budget == null ? (v) => categoryId = v : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Limite mensal', prefixText: 'R\$ '),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Repetir todo mês'),
              subtitle: Text(recurring ? 'Vale de $month em diante' : 'Vale só em $month'),
              value: recurring,
              onChanged: (v) => setDialog(() => recurring = v),
            ),
          ]),
          actions: [
            if (budget != null)
              TextButton(
                onPressed: () async {
                  try {
                    // Herdado: para de repetir daqui em diante. Criado neste mês: apaga.
                    await state.api.deleteBudget(budget.id, state.monthKey);
                    if (c.mounted) Navigator.pop(c, true);
                  } catch (e) {
                    if (c.mounted) showError(c, e);
                  }
                },
                child: Text(budget.inherited ? 'Parar de repetir' : 'Excluir'),
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
        ),
      ),
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
          builder: (context, d, _) => ListView(padding: const EdgeInsets.all(16), children: [
            if (d.budgets.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('Defina limites de gasto por categoria e acompanhe ao longo do mês.',
                    textAlign: TextAlign.center),
              ),
            ...d.budgets.map((b) => Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: BudgetProgress(b, onLongPress: () => _edit(context, budget: b)),
                  ),
                )),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Icons.add),
              label: const Text('Adicionar orçamento'),
            ),
            if (d.budgets.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Pressione e segure um orçamento para editar.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              ),
          ]),
        ),
      ),
    ]);
  }
}
