import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Categorias do usuário, separadas em despesas e receitas (RN-31).
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = context.watch<AppState>().categories;
    return DefaultTabController(
      length: 2,
      child: Builder(builder: (context) {
        final tabs = DefaultTabController.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Categorias'),
            bottom: const TabBar(tabs: [Tab(text: 'Despesas'), Tab(text: 'Receitas')]),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showCategorySheet(context,
                type: tabs.index == 0 ? TxType.expense : TxType.income),
            icon: const Icon(Icons.add),
            label: const Text('Nova categoria'),
          ),
          body: TabBarView(children: [
            for (final type in [TxType.expense, TxType.income])
              _CategoryList(categories.where((c) => c.type == type).toList()),
          ]),
        );
      }),
    );
  }
}

class _CategoryList extends StatelessWidget {
  final List<TxCategory> items;
  const _CategoryList(this.items);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const EmptyState(icon: Icons.category_outlined, title: 'Nenhuma categoria ainda');
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 104), children: [
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, c) in items.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 72),
            ListTile(
              leading: IconBadge(categoryIcon(c.icon), hexColor(c.color)),
              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showCategorySheet(context, editing: c),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// Cria ou edita uma categoria. Devolve a categoria salva (ou null se cancelar ou excluir).
Future<TxCategory?> showCategorySheet(BuildContext context, {TxCategory? editing, TxType? type}) =>
    showModalBottomSheet<TxCategory>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SafeArea(
        top: false,
        child: _CategorySheet(editing: editing, type: type ?? editing?.type ?? TxType.expense),
      ),
    );

class _CategorySheet extends StatefulWidget {
  final TxCategory? editing;
  final TxType type;
  const _CategorySheet({this.editing, required this.type});
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late final _name = TextEditingController(text: widget.editing?.name);
  late TxType _type = widget.type;
  late String _icon = widget.editing?.icon ?? 'category';
  late String _color = widget.editing?.color ?? categoryColors.first;
  bool _busy = false;

  Future<void> _save() async {
    final state = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final saved = await state.api.saveCategory(
        id: widget.editing?.id,
        name: _name.text.trim(),
        type: _type,
        icon: _icon,
        color: _color,
      );
      state.dataChanged();
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: expenseColor),
        title: Text('Excluir "${widget.editing!.name}"?'),
        content: const Text('Os orçamentos dessa categoria também serão excluídos.'),
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
    setState(() => _busy = true);
    try {
      await state.api.deleteCategory(widget.editing!.id);
      state.dataChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = hexColor(_color);
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.editing == null ? 'Nova categoria' : 'Editar categoria',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          // Prévia de como a categoria aparece nos lançamentos.
          Row(children: [
            IconBadge(categoryIcon(_icon), color, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: _name,
                builder: (_, v, _) => Text(v.text.isEmpty ? 'Nome da categoria' : v.text,
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            autofocus: widget.editing == null,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Pets, Academia, Presentes'),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TxType>(
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text('Despesa'), icon: Icon(Icons.north_east)),
              ButtonSegment(value: TxType.income, label: Text('Receita'), icon: Icon(Icons.south_west)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 20),
          Text('Ícone', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in categoryIcons.entries)
              InkWell(
                onTap: () => setState(() => _icon = e.key),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: e.key == _icon ? color.withValues(alpha: .16) : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: e.key == _icon ? color : Colors.transparent, width: 2),
                  ),
                  child: Icon(e.value, size: 22, color: e.key == _icon ? color : cs.onSurfaceVariant),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          Text('Cor', style: text.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in categoryColors)
              GestureDetector(
                onTap: () => setState(() => _color = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: hexColor(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: c == _color ? cs.onSurface : Colors.transparent, width: 3),
                  ),
                  child: c == _color ? Icon(Icons.check, size: 18, color: onColor(hexColor(c))) : null,
                ),
              ),
          ]),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(widget.editing == null ? 'Criar categoria' : 'Salvar'),
          ),
          if (widget.editing != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: expenseColor),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir categoria'),
            ),
          ],
        ]),
      ),
    );
  }
}
