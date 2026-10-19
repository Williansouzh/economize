import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'transactions_screen.dart';

/// Busca lançamentos de todos os meses por texto, tipo, categoria e conta.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  TxType? _type;
  String? _categoryId, _accountId;
  List<Transaction>? _results;
  bool _loading = false;
  Object? _error;
  int _revision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Editou ou excluiu um resultado: busca de novo.
    final revision = context.watch<AppState>().revision;
    if (revision != _revision) {
      _revision = revision;
      if (_results != null) _search();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  bool get _hasFilter => _query.text.trim().isNotEmpty || _type != null || _categoryId != null || _accountId != null;

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    if (!_hasFilter) {
      setState(() => _results = null);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await context.read<AppState>().api.searchTransactions(
        q: _query.text,
        type: _type,
        categoryId: _categoryId,
        accountId: _accountId,
      );
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(
    String title,
    List<(String id, String name, IconData icon, Color color)> options,
    String? current,
    ValueChanged<String?> onPicked,
  ) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: Theme.of(c).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Todas'),
              onTap: () => Navigator.pop(c, ''),
            ),
            for (final (id, name, icon, color) in options)
              ListTile(
                leading: IconBadge(icon, color, size: 34),
                title: Text(name),
                trailing: id == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(c, id),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    onPicked(picked.isEmpty ? null : picked);
    _search();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final category = state.categories.where((c) => c.id == _categoryId).firstOrNull;
    final account = state.accounts.where((a) => a.id == _accountId).firstOrNull;
    final results = _results;
    final total = results?.fold(0.0, (s, t) => s + (t.type == TxType.income ? t.amount : -t.amount));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (_) => _changed(),
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Buscar lançamentos',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _query.clear();
                      _search();
                    },
                  ),
          ),
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Despesas'),
                  selected: _type == TxType.expense,
                  onSelected: (v) {
                    setState(() => _type = v ? TxType.expense : null);
                    _search();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Receitas'),
                  selected: _type == TxType.income,
                  onSelected: (v) {
                    setState(() => _type = v ? TxType.income : null);
                    _search();
                  },
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.category_outlined, size: 18),
                  label: Text(category?.name ?? 'Categoria'),
                  selected: category != null,
                  onSelected: (_) => _pick(
                    'Categoria',
                    [
                      for (final c in state.categories.where((c) => _type == null || c.type == _type))
                        (c.id, c.name, categoryIcon(c.icon), hexColor(c.color)),
                    ],
                    _categoryId,
                    (id) => setState(() => _categoryId = id),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.account_balance_outlined, size: 18),
                  label: Text(account?.name ?? 'Conta'),
                  selected: account != null,
                  onSelected: (_) => _pick(
                    'Conta',
                    [for (final a in state.accounts) (a.id, a.name, accountIcon(a.icon), hexColor(a.color))],
                    _accountId,
                    (id) => setState(() => _accountId = id),
                  ),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: switch ((results, _error)) {
              (_, final Object e) => ErrorView(error: e, onRetry: _search),
              (null, _) => const EmptyState(
                icon: Icons.search,
                title: 'Busque em todos os meses',
                message: 'Digite parte da descrição ou da categoria, ou use os filtros acima.',
              ),
              (final r?, _) when r.isEmpty && !_loading => const EmptyState(
                icon: Icons.search_off,
                title: 'Nada encontrado',
                message: 'Tente outra palavra ou tire algum filtro.',
              ),
              (final r?, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.length >= 100 ? 'Mostrando os 100 mais recentes' : '${r.length} lançamento(s)',
                            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          money(total!),
                          style: TextStyle(fontWeight: FontWeight.w800, color: total >= 0 ? incomeColor : expenseColor),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final (i, t) in r.indexed) ...[
                          if (i > 0) const Divider(height: 1, indent: 72),
                          TransactionTile(t, showDate: true),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}
