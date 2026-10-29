import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'categories_screen.dart';

/// Converte "1.234,56" ou "1234.56" em double.
double? parseAmount(String text) {
  var s = text.trim().replaceAll('R\$', '').replaceAll(' ', '').replaceAll(' ', '');
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s);
}

enum _Kind { expense, income, transfer }

enum _Repeat { none, monthly, installments }

/// Sugestão de categoria pela descrição: primeiro o que a pessoa já lançou com esse texto,
/// depois palavras comuns. Devolve o nome da categoria padrão.
String? suggestCategoryName(String description) {
  final d = description.toLowerCase();
  const words = {
    'Transporte': ['uber', '99', 'taxi', 'táxi', 'ônibus', 'onibus', 'metrô', 'metro', 'combust', 'gasolina', 'estacion', 'pedágio'],
    'Mercado': ['mercado', 'supermerc', 'atacad', 'hortifruti', 'feira'],
    'Alimentação': ['ifood', 'restaurante', 'padaria', 'almoço', 'almoco', 'jantar', 'lanche', 'café', 'cafe', 'pizza', 'açaí', 'marmita'],
    'Assinaturas': ['netflix', 'spotify', 'prime', 'disney', 'max', 'youtube', 'icloud', 'assinatura', 'globoplay'],
    'Saúde': ['farmácia', 'farmacia', 'drogaria', 'consulta', 'médico', 'medico', 'dentista', 'exame', 'academia'],
    'Moradia': ['aluguel', 'condomínio', 'condominio', 'luz', 'energia', 'água', 'agua', 'internet', 'gás', 'iptu'],
    'Lazer': ['cinema', 'show', 'bar', 'festa', 'viagem', 'ingresso', 'jogo'],
    'Educação': ['curso', 'escola', 'faculdade', 'livro', 'mensalidade', 'inglês', 'ingles'],
    'Compras': ['roupa', 'shopping', 'loja', 'amazon', 'shopee', 'mercado livre', 'presente'],
    'Salário': ['salário', 'salario', 'pagamento empresa'],
    'Freelance': ['freela', 'projeto', 'cliente', 'job'],
  };
  for (final MapEntry(key: name, value: list) in words.entries) {
    if (list.any((w) => RegExp('(^|\\W)${RegExp.escape(w)}').hasMatch(d))) return name;
  }
  return null;
}

/// Cria ou edita uma despesa, uma receita ou uma transferência entre contas.
/// Valor grande com teclado próprio (centavos automáticos: 4590 = 45,90), categorias em grade por
/// frequência, conta lembrada e o Salvar sempre à vista. Meta: lançar em 3 toques.
class TransactionFormScreen extends StatefulWidget {
  final Transaction? editing;
  final Transfer? editingTransfer;

  /// "Lançar de novo": começa preenchido como este, mas é um lançamento novo, com a data de hoje.
  final Transaction? duplicate;

  /// Dentro da configuração guiada: sem a troca de tipo e sem fechar; avisa por [onSaved].
  final VoidCallback? onSaved;
  final String? prompt;
  const TransactionFormScreen({super.key, this.editing, this.editingTransfer, this.duplicate, this.onSaved, this.prompt});
  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  late final _tx = widget.editing;
  late final _tr = widget.editingTransfer;
  late final _base = widget.editing ?? widget.duplicate;
  late _Kind _kind = _tr != null ? _Kind.transfer : (_base?.type == TxType.income ? _Kind.income : _Kind.expense);
  late final _description = TextEditingController(text: _base?.description ?? _tr?.description);
  final _descriptionFocus = FocusNode();
  /// Uma por tela aberta: tocar em salvar de novo depois de uma falha de rede não duplica o lançamento.
  final _idempotencyKey = List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
  final _keyFocus = FocusNode();
  late int _cents = (((_base?.amount ?? _tr?.amount) ?? 0) * 100).round();
  late DateTime _date = _tx?.date ?? _tr?.date ?? DateTime.now();
  late bool _isPaid = _tx?.isPaid ?? _tr?.isPaid ?? true;
  late String? _accountId = _base?.accountId ?? _tr?.fromAccountId;
  late String? _toAccountId = _tr?.toAccountId;
  late String? _categoryId = _base?.categoryId;
  bool _categoryTouched = false;
  bool _suggested = false;
  // Criada agora pelo "Nova categoria": fica na lista até o AppState recarregar as categorias.
  TxCategory? _justCreated;
  bool _saving = false;
  _Repeat _repeat = _Repeat.none;
  int _months = 12, _installments = 2;

  bool get _isEditing => _tx != null || _tr != null;
  bool get _embedded => widget.onSaved != null;
  TxType get _type => _kind == _Kind.income ? TxType.income : TxType.expense;
  double get _amount => _cents / 100;

  @override
  void initState() {
    super.initState();
    _categoryTouched = _base != null;
    _description.addListener(_suggest);
    _descriptionFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    _descriptionFocus.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  // ---------- Teclado ----------
  void _digit(String d) {
    if ('$_cents'.length >= 11) return;
    HapticFeedback.selectionClick();
    setState(() => _cents = int.parse('$_cents$d'));
  }

  void _backspace() {
    HapticFeedback.selectionClick();
    setState(() => _cents = _cents ~/ 10);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    // Teclas digitadas num campo de texto (descrição, observação) sobem até aqui: são do campo, não do valor.
    if (FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null) {
      return KeyEventResult.ignored;
    }
    final ch = e.character;
    if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _digit(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter && !_saving) {
      _save();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------- Sugestão de categoria ----------
  void _suggest() {
    if (_categoryTouched || _kind == _Kind.transfer) return;
    final text = _description.text.trim();
    final state = context.read<AppState>();
    final categories = state.categories.where((c) => c.type == _type);
    String? id;
    if (text.length >= 3) {
      final name = suggestCategoryName(text);
      id = categories.where((c) => c.name == name).firstOrNull?.id;
    }
    if (id != null && id != _categoryId) {
      setState(() {
        _categoryId = id;
        _suggested = true;
      });
    } else if (id == null && _suggested) {
      setState(() => _suggested = false);
    }
  }

  // ---------- Salvar ----------
  Future<void> _save() async {
    final state = context.read<AppState>();
    final transfer = _kind == _Kind.transfer;
    if (_cents <= 0) {
      showError(context, 'Digite o valor.');
      return;
    }
    if (_accountId == null || (transfer ? _toAccountId == null : _categoryId == null)) {
      showError(context, transfer ? 'Escolha a conta de origem e a de destino.' : 'Escolha a categoria.');
      return;
    }
    if (transfer && _accountId == _toAccountId) {
      showError(context, 'Escolha contas de origem e destino diferentes.');
      return;
    }
    // Série (fixo ou parcelado): a mudança vale só para este ou também para os próximos?
    var future = false;
    if (!transfer && _tx != null && _tx.inSeries) {
      final choice = await askSeriesScope(context, editing: true);
      if (choice == null) return;
      future = choice;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    var firstEver = false;
    try {
      final p = await state.progress();
      firstEver = !_isEditing && !p.achievements.any((a) => a.id == 'first_entry' && a.unlocked);
    } catch (_) {}
    setState(() => _saving = true);
    String? createdId;
    final category = state.categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? _justCreated?.name;
    try {
      if (transfer) {
        await state.api.saveTransfer(
          id: _tr?.id,
          fromAccountId: _accountId!,
          toAccountId: _toAccountId!,
          amount: _amount,
          date: _date,
          description: _description.text.trim(),
          isPaid: _isPaid,
        );
      } else {
        createdId = await state.api.saveTransaction(
          id: _tx?.id,
          accountId: _accountId!,
          categoryId: _categoryId!,
          description: _description.text.trim(),
          amount: _amount,
          type: _type,
          date: _date,
          isPaid: _isPaid,
          repeat: switch (_repeat) {
            _Repeat.none => null,
            _Repeat.monthly => 'monthly',
            _Repeat.installments => 'installments',
          },
          repeatCount: _repeat == _Repeat.monthly ? _months : _installments,
          future: future,
          idempotencyKey: _idempotencyKey,
        );
        state.rememberCategory(_type, _categoryId!);
        state.rememberAccount(_accountId!);
      }
      HapticFeedback.lightImpact();
      state.dataChanged();
      if (_embedded) {
        widget.onSaved!();
        return;
      }
      navigator.pop();
      if (firstEver) {
        if (navigator.mounted) _celebrate(navigator.context);
      } else if (!_isEditing) {
        final series = _repeat != _Repeat.none;
        messenger.showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(transfer
              ? 'Transferência de ${money(_amount)} salva'
              : 'Lançado em $category · ${money(_amount)}'),
          action: createdId == null
              ? null
              : SnackBarAction(
                  label: 'Desfazer',
                  onPressed: () async {
                    try {
                      await state.api.deleteTransaction(createdId!, future: series);
                      state.dataChanged();
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                ),
        ));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Alterações salvas')));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Primeiro lançamento da vida: o Cofrinho comemora (conquista "Primeiro passo").
  static void _celebrate(BuildContext context) {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const MascotAvatar(size: 120, pose: MascotPose.celebrating, bounce: true),
            const SizedBox(height: 16),
            Text('Primeiro passo! 🎉', style: Theme.of(c).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Seu primeiro lançamento está salvo. Quanto mais você anota, melhor eu te ajudo a economizar.',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Bora!')),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final state = context.read<AppState>();
    var future = false;
    if (_tx != null && _tx.inSeries) {
      final choice = await askSeriesScope(context, editing: false);
      if (choice == null) return;
      future = choice;
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(_tr != null ? 'Excluir transferência?' : 'Excluir lançamento?'),
          content: Text(_description.text.isEmpty ? money(_amount) : '${_description.text} · ${money(_amount)}'),
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
    }
    try {
      if (_tr != null) {
        await state.api.deleteTransfer(_tr.id);
      } else {
        await state.api.deleteTransaction(_tx!.id, future: future);
      }
      state.dataChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  // ---------- Escolhas ----------
  Future<void> _pickAccount({required bool destination}) async {
    final state = context.read<AppState>();
    final exclude = destination ? _accountId : null;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                destination ? 'Vai para' : (_kind == _Kind.income ? 'Recebido em' : (_kind == _Kind.transfer ? 'Sai de' : 'Pago com')),
                style: Theme.of(c).textTheme.titleLarge,
              ),
            ),
            for (final a in state.accounts)
              if (a.id != exclude)
                ListTile(
                  leading: IconBadge(accountIcon(a.icon), tintOf(c, a.color)),
                  title: Text(a.name),
                  subtitle: Text(a.isCard ? 'Cartão de crédito' : 'Conta · saldo ${money(a.balance)}'),
                  trailing: a.id == (destination ? _toAccountId : _accountId)
                      ? Icon(Icons.check_rounded, color: Theme.of(c).colorScheme.primary)
                      : null,
                  onTap: () => Navigator.pop(c, a.id),
                ),
          ]),
        ),
      ),
    );
    if (picked != null) setState(() => destination ? _toAccountId = picked : _accountId = picked);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _moreCategories(List<TxCategory> all) async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Categoria', style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final cat in all)
                ChoiceChip(
                  avatar: Icon(categoryIcon(cat.icon), size: 18, color: tintOf(c, cat.color)),
                  label: Text(cat.name),
                  selected: cat.id == _categoryId,
                  showCheckmark: false,
                  onSelected: (_) => Navigator.pop(c, cat.id),
                ),
            ]),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(c, #create),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nova categoria'),
            ),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (picked == #create) {
      final created = await showCategorySheet(context, type: _type);
      if (created != null && mounted) {
        setState(() {
          _justCreated = created;
          _categoryId = created.id;
          _categoryTouched = true;
          _suggested = false;
        });
      }
    } else if (picked is String) {
      setState(() {
        _categoryId = picked;
        _categoryTouched = true;
        _suggested = false;
      });
    }
  }

  Future<void> _moreOptions() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, setSheet) {
        void update(VoidCallback f) {
          setState(f);
          setSheet(() {});
        }

        final cs = Theme.of(c).colorScheme;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));
        final day = DateTime(_date.year, _date.month, _date.day);
        final transfer = _kind == _Kind.transfer;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Mais opções', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('Data', style: Theme.of(c).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(label: const Text('Hoje'), selected: day == today, onSelected: (_) => update(() => _date = today)),
                ChoiceChip(
                    label: const Text('Ontem'), selected: day == yesterday, onSelected: (_) => update(() => _date = yesterday)),
                ChoiceChip(
                  avatar: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(day == today || day == yesterday ? 'Outra data' : DateFormat('dd/MM/yyyy').format(_date)),
                  selected: day != today && day != yesterday,
                  onSelected: (_) async {
                    await _pickDate();
                    setSheet(() {});
                  },
                ),
              ]),
              if (!transfer && !_isEditing) ...[
                const SizedBox(height: 20),
                Text('Repetir', style: Theme.of(c).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                      label: const Text('Não repete'),
                      selected: _repeat == _Repeat.none,
                      onSelected: (_) => update(() => _repeat = _Repeat.none)),
                  ChoiceChip(
                      label: const Text('Fixo todo mês'),
                      selected: _repeat == _Repeat.monthly,
                      onSelected: (_) => update(() => _repeat = _Repeat.monthly)),
                  if (_kind == _Kind.expense)
                    ChoiceChip(
                        label: const Text('Parcelado'),
                        selected: _repeat == _Repeat.installments,
                        onSelected: (_) => update(() => _repeat = _Repeat.installments)),
                ]),
                if (_repeat != _Repeat.none) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Text(_repeat == _Repeat.monthly ? 'Por' : 'Em'),
                    const SizedBox(width: 12),
                    DropdownButton<int>(
                      value: _repeat == _Repeat.monthly ? _months : _installments,
                      items: [
                        for (final n in _repeat == _Repeat.monthly
                            ? const [2, 3, 6, 12, 24, 36, 48, 60]
                            : List.generate(23, (i) => i + 2))
                          DropdownMenuItem(value: n, child: Text(_repeat == _Repeat.monthly ? '$n meses' : '${n}x')),
                      ],
                      onChanged: (n) => update(() => _repeat == _Repeat.monthly ? _months = n! : _installments = n!),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _repeat == _Repeat.monthly
                            ? 'Um lançamento por mês, a partir da data.'
                            : '${_installments}x de ${money(_amount / _installments)} (o valor digitado é o total)',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ]),
                ],
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(switch (_kind) {
                  _Kind.income => 'Já recebi',
                  _Kind.expense => 'Já paguei',
                  _Kind.transfer => 'Já aconteceu',
                }),
                subtitle: Text(_isPaid ? 'Entra no saldo de hoje' : 'Fica pendente e entra só no previsto'),
                value: _isPaid,
                onChanged: (v) => update(() => _isPaid = v),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Pronto')),
            ]),
          ),
        );
      }),
    );
  }

  // ---------- Tela ----------
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final transfer = _kind == _Kind.transfer;
    final all = state.categoriesByUse(_type);
    if (_justCreated case final c? when c.type == _type && !all.any((x) => x.id == c.id)) all.add(c);
    if (!all.any((c) => c.id == _categoryId)) _categoryId = null;
    // Lançamento rápido: começa com a última categoria usada nesse tipo.
    if (!_isEditing && _categoryId == null && !_categoryTouched && !_suggested) {
      final last = state.lastCategory(_type);
      if (all.any((c) => c.id == last)) _categoryId = last;
    }
    _accountId ??= state.defaultAccountId;
    if (transfer && _toAccountId == _accountId) _toAccountId = null;
    final account = state.accounts.where((a) => a.id == _accountId).firstOrNull;
    final toAccount = state.accounts.where((a) => a.id == _toAccountId).firstOrNull;

    // Grade 4×2: as 7 mais usadas + "Mais". A escolhida em "Mais" entra no 7º lugar.
    final grid = all.take(7).toList();
    if (_categoryId != null && !grid.any((c) => c.id == _categoryId)) {
      final chosen = all.firstWhere((c) => c.id == _categoryId);
      if (grid.length == 7) grid.removeLast();
      grid.add(chosen);
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(_date.year, _date.month, _date.day);
    final dateLabel = day == today
        ? 'Hoje'
        : day == today.subtract(const Duration(days: 1))
            ? 'Ontem'
            : DateFormat("d 'de' MMM", 'pt_BR').format(_date);
    final extras = [
      if (_repeat == _Repeat.monthly) 'Fixo por $_months meses',
      if (_repeat == _Repeat.installments) '${_installments}x de ${money(_amount / _installments)}',
      if (!_isPaid) 'Pendente',
      if (_tx?.installmentCount case final n?) 'Parcela ${_tx!.installmentNumber} de $n',
    ];
    final keypadVisible = !_descriptionFocus.hasFocus;
    final saveLabel = _isEditing
        ? 'Salvar alterações'
        : switch (_kind) {
            _Kind.expense => 'Salvar despesa',
            _Kind.income => 'Salvar receita',
            _Kind.transfer => 'Salvar transferência',
          };

    final body = Focus(
      focusNode: _keyFocus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(children: [
        if (!_embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
            child: Row(children: [
              IconButton(
                tooltip: 'Fechar',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.maybePop(context),
              ),
              Expanded(child: _KindSwitch(kind: _kind, editingTx: _tx != null, editingTransfer: _tr != null, onChanged: (k) {
                setState(() {
                  _kind = k;
                  _categoryId = null;
                  _categoryTouched = false;
                  _suggested = false;
                  if (_kind != _Kind.expense && _repeat == _Repeat.installments) _repeat = _Repeat.none;
                });
                _suggest();
              })),
              if (_isEditing)
                IconButton(
                  tooltip: 'Excluir',
                  icon: Icon(Icons.delete_outline_rounded, color: context.colors.expense),
                  onPressed: _delete,
                ),
            ]),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                widget.prompt ??
                    switch (_kind) {
                      _ when _repeat == _Repeat.installments => 'Valor total da compra',
                      _Kind.income => 'Quanto você recebeu?',
                      _Kind.expense => 'Quanto você gastou?',
                      _Kind.transfer => 'Quanto você vai mover?',
                    },
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  _descriptionFocus.unfocus();
                  _keyFocus.requestFocus();
                },
                child: Semantics(
                  label: 'Valor: ${money(_amount)}',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('R\$ ', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(amountText(_amount),
                              style: TextStyle(
                                  fontSize: 52,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1,
                                  color: _cents == 0 ? cs.onSurfaceVariant.withValues(alpha: .6) : cs.onSurface)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _DescriptionField(
                controller: _description,
                focus: _descriptionFocus,
                optional: transfer,
                suggested: _suggested,
              ),
              const SizedBox(height: 16),
              if (transfer) ...[
                _AccountPicker(label: 'Sai de', account: account, onTap: () => _pickAccount(destination: false)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Icon(Icons.south_rounded),
                ),
                if (state.accounts.length < 2)
                  Text('Crie outra conta no Início para transferir entre elas.',
                      textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant))
                else
                  _AccountPicker(label: 'Vai para', account: toAccount, onTap: () => _pickAccount(destination: true)),
              ] else
                _CategoryGrid(
                  categories: grid,
                  selected: _categoryId,
                  onSelect: (id) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _categoryId = id;
                      _categoryTouched = true;
                      _suggested = false;
                    });
                  },
                  onMore: () => _moreCategories(all),
                ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (!transfer)
                  _DropChip(
                    icon: account == null ? Icons.account_balance_wallet_outlined : accountIcon(account.icon),
                    iconColor: account == null ? null : tintOf(context, account.color),
                    label: account?.name ?? 'Conta',
                    onTap: () => _pickAccount(destination: false),
                  ),
                _DropChip(icon: Icons.event_outlined, label: dateLabel, onTap: _pickDate),
                TextButton(onPressed: _moreOptions, child: const Text('Mais opções')),
              ]),
              if (extras.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(extras.join(' · '),
                      style: TextStyle(fontWeight: FontWeight.w700, color: context.colors.onWarningSoft)),
                ),
              if (_tx != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Para virar transferência, exclua este lançamento e lance de novo.',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: keypadVisible ? _Keypad(onDigit: _digit, onBackspace: _backspace) : const SizedBox(width: double.infinity),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + (_embedded ? 0 : MediaQuery.paddingOf(context).bottom)),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(saveLabel),
            ),
          ),
        ),
      ]),
    );
    if (_embedded) return body;
    return Scaffold(body: SafeArea(bottom: false, child: body));
  }
}

/// Despesa · Receita · Transferir. Na edição, lançamento e transferência não trocam entre si.
class _KindSwitch extends StatelessWidget {
  final _Kind kind;
  final bool editingTx, editingTransfer;
  final ValueChanged<_Kind> onChanged;
  const _KindSwitch({required this.kind, required this.editingTx, required this.editingTransfer, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(_Kind k, String label, bool enabled) {
      final selected = k == kind;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          enabled: enabled,
          child: GestureDetector(
            onTap: enabled ? () => onChanged(k) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? cs.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (selected) ...[Icon(Icons.check_rounded, size: 16, color: cs.onPrimaryContainer), const SizedBox(width: 4)],
                Text(label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: !enabled
                          ? cs.onSurfaceVariant.withValues(alpha: .4)
                          : selected
                              ? cs.onPrimaryContainer
                              : cs.onSurfaceVariant,
                    )),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .7), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        seg(_Kind.expense, 'Despesa', !editingTransfer),
        seg(_Kind.income, 'Receita', !editingTransfer),
        seg(_Kind.transfer, 'Transferir', !editingTx),
      ]),
    );
  }
}

class _DescriptionField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool optional, suggested;
  const _DescriptionField({required this.controller, required this.focus, required this.optional, required this.suggested});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      focusNode: focus,
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => focus.unfocus(),
      decoration: InputDecoration(
        hintText: optional ? 'Descrição (opcional)' : 'Descrição (ex.: almoço, Uber)',
        prefixIcon: const Icon(Icons.notes_rounded),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: .6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        suffixIcon: suggested
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text('Sugeri a categoria',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.primary)),
                ),
              )
            : null,
      ),
    );
  }
}

/// Grade 4×2 das categorias mais usadas + "Mais".
class _CategoryGrid extends StatelessWidget {
  final List<TxCategory> categories;
  final String? selected;
  final ValueChanged<String> onSelect;
  final VoidCallback onMore;
  const _CategoryGrid({required this.categories, required this.selected, required this.onSelect, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget tile({required Widget icon, required String label, required bool isSelected, required VoidCallback onTap}) =>
        Semantics(
          button: true,
          selected: isSelected,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? cs.primaryContainer : cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? cs.onPrimaryContainer : cs.outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                icon,
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700)),
              ]),
            ),
          ),
        );
    final tiles = [
      for (final c in categories)
        tile(
          icon: IconBadge(categoryIcon(c.icon), tintOf(context, c.color), size: 36),
          label: c.name,
          isSelected: c.id == selected,
          onTap: () => onSelect(c.id),
        ),
      tile(
        icon: IconBadge(Icons.more_horiz_rounded, cs.onSurfaceVariant, size: 36),
        label: 'Mais',
        isSelected: false,
        onTap: onMore,
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 8.0;
      final w = (c.maxWidth - gap * 3) / 4;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

class _AccountPicker extends StatelessWidget {
  final String label;
  final Account? account;
  final VoidCallback onTap;
  const _AccountPicker({required this.label, required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = account;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: a == null
            ? const Icon(Icons.account_balance_wallet_outlined)
            : IconBadge(accountIcon(a.icon), tintOf(context, a.color)),
        title: Text(a?.name ?? 'Escolher conta'),
        subtitle: Text(label),
        trailing: const Icon(Icons.expand_more_rounded),
      ),
    );
  }
}

class _DropChip extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback onTap;
  const _DropChip({required this.icon, required this.label, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: iconColor ?? cs.onSurfaceVariant),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: 18, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}

/// Teclado numérico próprio: 1–9, "00", 0 e apagar. Os dois últimos dígitos são os centavos.
class _Keypad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  const _Keypad({required this.onDigit, required this.onBackspace});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, Widget? child}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Material(
              color: cs.surfaceContainerHighest.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap ?? () => onDigit(label),
                child: SizedBox(
                  height: 52,
                  child: Center(
                    child: child ?? Text(label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(children: [for (final d in row) key(d)]),
        Row(children: [
          key('00', onTap: () {
            onDigit('0');
            onDigit('0');
          }),
          key('0'),
          key('',
              onTap: onBackspace,
              child: Semantics(label: 'Apagar', child: const Icon(Icons.backspace_outlined))),
        ]),
      ]),
    );
  }
}

/// Pergunta se a ação vale só para este lançamento da série ou também para os próximos.
/// Devolve null se o usuário cancelar.
Future<bool?> askSeriesScope(BuildContext context, {required bool editing}) => showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.repeat_rounded),
        title: Text(editing ? 'Salvar alterações em' : 'Excluir'),
        content: const Text('Este lançamento faz parte de uma série (fixo ou parcelado).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Só este')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Este e os próximos')),
        ],
      ),
    );
