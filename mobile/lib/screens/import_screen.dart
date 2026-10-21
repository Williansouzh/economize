import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import 'account_sheet.dart';

/// Importar extrato (RN-42): escolhe a conta e o arquivo (OFX, CSV ou PDF exportado do banco),
/// depois revisa e confirma.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String? _accountId;
  bool _busy = false;

  Future<void> _pick() async {
    final state = context.read<AppState>();
    final accountId = _accountId ?? state.defaultAccountId;
    if (accountId == null) {
      showError(context, 'Crie uma conta primeiro.');
      return;
    }
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['ofx', 'csv', 'pdf', 'txt']);
    final file = picked.singleOrNull;
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) throw ApiException('O arquivo pode ter no máximo 5 MB.');
      final lines = await state.api.importParse(file.name, bytes);
      if (!mounted) return;
      final account = state.accounts.firstWhere((a) => a.id == accountId);
      // Fatura de cartão em CSV costuma trazer as compras como valores positivos.
      final mostlyPositive = lines.where((l) => l.amount > 0).length > lines.length / 2;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImportReviewScreen(
            title: file.name,
            lines: lines,
            accountId: accountId,
            allowInvert: true,
            invert: account.isCard && mostlyPositive,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    _accountId ??= state.defaultAccountId;
    Widget step(String n, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: cs.primaryContainer,
            child: Text(
              n,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Importar extrato')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          const Center(child: IconBadge(Icons.upload_file, Color(0xFF3E7BFA), size: 72)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  step('1', 'No app ou site do banco, exporte o extrato ou a fatura do cartão em OFX, CSV ou PDF.'),
                  step('2', 'Escolha abaixo em qual conta ou cartão do Economizze eles entram.'),
                  step('3', 'Revise: o app sugere a categoria e avisa o que já foi lançado.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(
              labelText: 'Conta ou cartão',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
            items: [for (final a in state.accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.folder_open),
            label: Text(_busy ? 'Lendo o arquivo...' : 'Escolher arquivo'),
          ),
          const SizedBox(height: 12),
          Text(
            'OFX e CSV são lidos no nosso servidor. O PDF é lido com a ajuda da IA, que recebe só o texto do '
            'arquivo. Nada é gravado antes de você confirmar.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Revisão antes de gravar: conta, categoria de cada linha, o que fica de fora. Usada também
/// pelos gastos detectados nas notificações. Devolve o número de lançamentos criados.
class ImportReviewScreen extends StatefulWidget {
  final String title;
  final List<ImportLine> lines;
  final String accountId;
  final bool allowInvert, invert;
  final ValueChanged<String>? onAccountChanged;
  const ImportReviewScreen({
    super.key,
    required this.title,
    required this.lines,
    required this.accountId,
    this.allowInvert = false,
    this.invert = false,
    this.onAccountChanged,
  });
  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  late String _accountId = widget.accountId;
  late bool _invert = widget.invert;
  List<ImportItem>? _items;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    final lines = _invert
        ? [for (final l in widget.lines) ImportLine(l.date, l.description, -l.amount, l.externalId)]
        : widget.lines;
    try {
      final items = await context.read<AppState>().api.importPreview(_accountId, lines);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// O extrato traz o que entrou e saiu, não o saldo de antes do primeiro dia; e aplicações na caixinha
  /// e pagamentos de fatura costumam ficar de fora. Por isso, depois de importar, o saldo é conferido.
  Future<void> _checkBalance(Account? account) async {
    if (account == null || account.isCard) return;
    final fix = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.account_balance_wallet_outlined),
        title: Text('Saldo do ${account.name}: ${money(account.balance)}'),
        content: const Text('É o mesmo que aparece hoje no app do banco?\n\n'
            'O extrato não traz o saldo de antes do primeiro dia, e o que foi para a caixinha ou para pagar a fatura '
            'fica de fora da importação. Se não bater, corrija o saldo atual: os lançamentos continuam iguais.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Está certo')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Corrigir saldo')),
        ],
      ),
    );
    if (fix == true && mounted) await showAccountSheet(context, editing: account);
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final chosen = _items!.where((i) => i.selected).toList();
    if (chosen.any((i) => i.categoryId == null)) {
      showError(context, 'Escolha a categoria de todos os lançamentos marcados.');
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await state.api.importCommit(_accountId, chosen);
      state.dataChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(created == 1 ? '1 lançamento importado.' : '$created lançamentos importados.')),
      );
      await state.loadReferenceData();
      if (!mounted) return;
      await _checkBalance(state.accounts.where((a) => a.id == _accountId).firstOrNull);
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCategory(ImportItem item) async {
    final categories = context.read<AppState>().categories.where((c) => c.type == item.type).toList();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => ListView(
        shrinkWrap: true,
        children: [
          for (final cat in categories)
            ListTile(
              leading: IconBadge(categoryIcon(cat.icon), hexColor(cat.color), size: 36),
              title: Text(cat.name),
              trailing: cat.id == item.categoryId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, cat.id),
            ),
        ],
      ),
    );
    if (chosen != null) setState(() => item.categoryId = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    final selected = items?.where((i) => i.selected).toList() ?? [];
    final out = selected.where((i) => i.type == TxType.expense).fold(0.0, (s, i) => s + i.amount);
    final inc = selected.where((i) => i.type == TxType.income).fold(0.0, (s, i) => s + i.amount);
    final categories = {for (final c in state.categories) c.id: c};
    final dates = DateFormat('dd/MM');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (items != null && items.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                final all = items.every((i) => i.selected);
                for (final i in items) {
                  i.selected = !all;
                }
              }),
              child: Text(items.every((i) => i.selected) ? 'Desmarcar' : 'Marcar todos'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Entram na conta', isDense: true),
              items: [for (final a in state.accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) {
                if (v == null || v == _accountId) return;
                _accountId = v;
                widget.onAccountChanged?.call(v);
                _load();
              },
            ),
          ),
          if (widget.allowInvert)
            SwitchListTile(
              dense: true,
              title: const Text('Inverter entradas e saídas'),
              subtitle: const Text('Use se as compras aparecerem como entradas (comum em fatura de cartão)'),
              value: _invert,
              onChanged: (v) {
                _invert = v;
                _load();
              },
            ),
          Expanded(
            child: _error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : items == null
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? const EmptyState(icon: Icons.inbox_outlined, title: 'Nada para importar')
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final cat = categories[item.categoryId];
                      final warning = switch (item.status) {
                        'imported' => 'Já importado',
                        'duplicate' => 'Parece já lançado',
                        _ => item.transferLike ? 'Parece transferência ou pagamento de fatura' : null,
                      };
                      return CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        value: item.selected,
                        onChanged: (v) => setState(() => item.selected = v ?? false),
                        title: Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(dates.format(item.date)),
                                ActionChip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(
                                    cat == null ? Icons.help_outline : categoryIcon(cat.icon),
                                    size: 16,
                                    color: cat == null ? cs.error : hexColor(cat.color),
                                  ),
                                  label: Text(cat?.name ?? 'Escolher categoria'),
                                  onPressed: () => _pickCategory(item),
                                ),
                              ],
                            ),
                            if (warning != null)
                              Text(
                                warning,
                                style: const TextStyle(color: warningColor, fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                          ],
                        ),
                        secondary: Text(
                          '${item.type == TxType.expense ? '-' : '+'}${money(item.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: item.type == TxType.expense ? expenseColor : incomeColor,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: items == null || items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Saídas ${money(out)} · Entradas ${money(inc)}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving || selected.isEmpty ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(
                                selected.length == 1
                                    ? 'Importar 1 lançamento'
                                    : 'Importar ${selected.length} lançamentos',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
