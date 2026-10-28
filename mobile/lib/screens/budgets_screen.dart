import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/month_loader.dart';
import 'goals.dart';
import 'profiles_screen.dart';
import 'transaction_form_screen.dart';

/// Planejar em duas partes: Orçamentos (limites por categoria) e Metas (economia com prazo).
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      MonthSelector(onTapLabel: () => showProfileSheet(context)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: PillSegments(labels: const ['Orçamentos', 'Metas'], selected: _tab, onChanged: (i) => setState(() => _tab = i)),
      ),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 210),
          switchInCurve: Curves.easeOutCubic,
          child: _tab == 0
              ? const KeyedSubtree(key: ValueKey('budgets'), child: _BudgetsTab())
              : ListView(key: const ValueKey('goals'), padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: const [GoalsSection()]),
        ),
      ),
    ]);
  }
}

class _BudgetsTab extends StatelessWidget {
  const _BudgetsTab();

  @override
  Widget build(BuildContext context) => MonthLoader<Dashboard>(
        load: (s) => s.dashboard(),
        builder: (context, d, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (d.budgets.isEmpty)
              Card(
                child: EmptyState(
                  icon: Icons.savings_outlined,
                  mascot: true,
                  title: 'Nenhum orçamento ainda',
                  message: 'Defina quanto quer gastar por mês em cada categoria. Eu aviso antes de você estourar.',
                  action: FilledButton.icon(
                    onPressed: () => showBudgetSheet(context),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Criar orçamento'),
                  ),
                ),
              )
            else ...[
              _BudgetsSummary(d.budgets),
              const SizedBox(height: Space.lg),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (final (i, b) in d.budgets.indexed) ...[
                    if (i > 0) const Divider(height: 1, indent: 68),
                    BudgetRow(b, onTap: () => showBudgetSheet(context, budget: b)),
                  ],
                  const Divider(height: 1, indent: 68),
                  ListTile(
                    minTileHeight: 56,
                    leading: SizedBox(width: 40, child: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary)),
                    title: Text('Novo orçamento',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                    onTap: () => showBudgetSheet(context),
                  ),
                ]),
              ),
            ],
          ],
        ),
      );
}

/// Orçamento: nome e "Restam R$ 121" (16/800) na 1ª linha; "R$ 1.078 de 1.200" na 2ª; barra de 8 dp
/// na cor de status (mar até 79%, alerta de 80% a 99%, despesa a partir de 100%) com o marcador de hoje.
class BudgetRow extends StatelessWidget {
  final Budget b;
  final VoidCallback? onTap;
  const BudgetRow(this.b, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final colors = context.colors;
    final over = b.spent > b.limit;
    final status = colors.forProgress(b.progress);
    final category = state.categories.where((c) => c.id == b.categoryId).firstOrNull;
    final month = state.month;
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(children: [
          IconBadge(categoryIcon(category?.icon ?? ''), tintOf(context, b.categoryColor)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(b.categoryName,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                const SizedBox(width: 8),
                Text(over ? 'Passou ${moneyShort(b.spent - b.limit)}' : 'Restam ${moneyShort(b.limit - b.spent)}',
                    style: valueStyle.copyWith(color: b.progress >= .8 ? status : cs.onSurface)),
              ]),
              const SizedBox(height: 8),
              StatusBar(value: b.progress, color: status, marker: isCurrent ? now.day / daysInMonth : null),
              const SizedBox(height: 4),
              Row(children: [
                Text('${moneyShort(b.spent)} de ${moneyShort(b.limit)}', style: Theme.of(context).textTheme.bodySmall),
                if (b.recurring) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.repeat_rounded, size: 14, color: cs.onSurfaceVariant, semanticLabel: 'repete todo mês'),
                ],
                const Spacer(),
                if (b.progress >= .8 && !over)
                  StatusBadge.warning(context, 'atenção')
                else
                  Text('${(b.progress * 100).round()}%', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ]),
      ),
    );
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
    final near = budgets.where((b) => b.progress >= .8 && b.spent <= b.limit).length;
    // O anel acompanha a pior categoria: 76% no total com uma categoria a 90% não é "tudo verde".
    final worst = budgets.map((b) => b.progress).fold(0.0, (a, b) => a > b ? a : b);
    final progress = limit == 0 ? 0.0 : spent / limit;
    final colors = context.colors;
    final color = colors.forProgress(worst >= .8 ? worst : progress);
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Row(children: [
          SizedBox(
            width: 80,
            height: 80,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0, 1)),
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Stack(fit: StackFit.expand, children: [
                CircularProgressIndicator(
                  value: v,
                  strokeWidth: 9,
                  strokeCap: StrokeCap.round,
                  color: color,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
                Center(child: Text('${(progress * 100).round()}%', style: valueStyle.copyWith(fontSize: 18))),
              ]),
            ),
          ),
          const SizedBox(width: Space.xl),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Orçamento do mês', style: Theme.of(context).textTheme.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('Restam ${moneyShort((limit - spent).clamp(0, double.infinity))}',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Text('${moneyShort(spent)} de ${moneyShort(limit)}', style: Theme.of(context).textTheme.bodySmall),
              if (over > 0 || near > 0) ...[
                const SizedBox(height: 6),
                Text(
                  over > 0
                      ? (over == 1 ? '1 categoria passou do limite' : '$over categorias passaram do limite')
                      : (near == 1 ? '1 categoria perto do limite' : '$near categorias perto do limite'),
                  style: TextStyle(color: over > 0 ? colors.expense : colors.warning, fontWeight: FontWeight.w800),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Cria ou edita um orçamento, numa folha de baixo.
Future<void> showBudgetSheet(BuildContext context, {Budget? budget}) async {
  final state = context.read<AppState>();
  final ok = await showAppSheet<bool>(context, builder: (_) => _BudgetSheet(budget: budget));
  if (ok == true) state.dataChanged();
}

class _BudgetSheet extends StatefulWidget {
  final Budget? budget;
  const _BudgetSheet({this.budget});
  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  late String? _categoryId = widget.budget?.categoryId;
  late final _limit = TextEditingController(text: widget.budget == null ? null : amountText(widget.budget!.limit));
  late bool _recurring = widget.budget?.recurring ?? true;
  bool _busy = false;

  Future<void> _save() async {
    final state = context.read<AppState>();
    final value = parseAmount(_limit.text);
    if (_categoryId == null || value == null || value <= 0) {
      showError(context, 'Escolha a categoria e o limite.');
      return;
    }
    setState(() => _busy = true);
    try {
      await state.api.saveBudget(_categoryId!, state.monthKey, value, recurring: _recurring);
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    try {
      await state.api.deleteBudget(widget.budget!.id, state.monthKey);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final budget = widget.budget;
    final inherited = budget?.inherited ?? false;
    final cats = state.categoriesByUse(TxType.expense);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(budget == null ? 'Novo orçamento' : 'Orçamento de ${budget.categoryName}'),
      if (inherited)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Este limite vem de ${monthLabel(DateTime.parse('${budget!.month}-01'))} e se repete todo mês. '
            'Salvar aqui muda a partir de ${monthLabel(state.month)}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      if (budget == null) ...[
        Text('Categoria', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in cats)
            ChoiceChip(
              avatar: _categoryId == c.id ? null : Icon(categoryIcon(c.icon), size: 18, color: tintOf(context, c.color)),
              label: Text(c.name),
              selected: _categoryId == c.id,
              onSelected: (_) => setState(() => _categoryId = c.id),
            ),
        ]),
        const SizedBox(height: 16),
      ],
      TextField(
        controller: _limit,
        autofocus: budget != null,
        keyboardType: TextInputType.number,
        inputFormatters: [MoneyInputFormatter()],
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        decoration: const InputDecoration(labelText: 'Limite por mês', prefixText: 'R\$ '),
      ),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Repetir todo mês'),
        subtitle: Text(_recurring ? 'Vale também para os próximos meses' : 'Só para ${monthLabel(state.month)}'),
        value: _recurring,
        onChanged: (v) => setState(() => _recurring = v),
      ),
      const SizedBox(height: 12),
      FilledButton(onPressed: _busy ? null : _save, child: Text(budget == null ? 'Criar orçamento' : 'Salvar')),
      if (budget != null) ...[
        const SizedBox(height: 8),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: context.colors.expense),
          onPressed: _busy ? null : _delete,
          child: Text(inherited ? 'Parar de repetir' : 'Excluir orçamento'),
        ),
      ],
    ]);
  }
}
