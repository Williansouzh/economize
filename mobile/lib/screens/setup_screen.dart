import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'transaction_form_screen.dart';
import 'whatsapp_screen.dart';

/// Configuração guiada logo depois de criar a conta: carteira, bancos, orçamentos e WhatsApp.
/// Cada passo salva ao continuar, então dá para fechar no meio sem perder o que já foi feito.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _Bank {
  final String name, color;
  const _Bank(this.name, this.color);
}

const _banks = [
  _Bank('Nubank', '#8A05BE'),
  _Bank('Itaú', '#EC7000'),
  _Bank('Bradesco', '#CC092F'),
  _Bank('Banco do Brasil', '#F9C900'),
  _Bank('Caixa', '#0070AF'),
  _Bank('Santander', '#EC0000'),
  _Bank('Inter', '#FF7A00'),
  _Bank('C6 Bank', '#242424'),
  _Bank('PicPay', '#21C25E'),
  _Bank('Mercado Pago', '#00B1EA'),
];

/// Categorias padrão sugeridas para o primeiro orçamento.
const _budgetCategories = ['Alimentação', 'Transporte', 'Lazer', 'Compras'];

class _SetupScreenState extends State<SetupScreen> {
  static const _steps = 6;
  int _step = 0;
  bool _busy = false;

  final _wallet = TextEditingController();
  final _selectedBanks = <String>{};
  final _bankBalances = <String, TextEditingController>{};
  final _budgets = {for (final c in _budgetCategories) c: TextEditingController()};

  // Resumo para a tela final.
  int _accountsCreated = 0, _budgetsCreated = 0;

  AppState get _state => context.read<AppState>();

  Future<void> _run(Future<void> Function() save) async {
    setState(() => _busy = true);
    try {
      await save();
      _state.dataChanged();
      if (mounted) setState(() => _step++);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveWallet() async {
    final value = parseAmount(_wallet.text) ?? 0;
    final wallet = _state.accounts.where((a) => a.name == 'Carteira').firstOrNull ?? _state.accounts.firstOrNull;
    if (wallet == null || value == wallet.initialBalance) return;
    await _state.api.saveAccount(
        id: wallet.id, name: wallet.name, initialBalance: value, color: wallet.color, icon: wallet.icon);
  }

  Future<void> _saveBanks() async {
    final existing = _state.accounts.map((a) => a.name.toLowerCase()).toSet();
    for (final bank in _banks.where((b) => _selectedBanks.contains(b.name))) {
      if (existing.contains(bank.name.toLowerCase())) continue;
      await _state.api.saveAccount(
        name: bank.name,
        initialBalance: parseAmount(_bankBalances[bank.name]?.text ?? '') ?? 0,
        color: bank.color,
        icon: 'account_balance',
      );
      _accountsCreated++;
    }
  }

  Future<void> _saveBudgets() async {
    for (final MapEntry(key: name, value: field) in _budgets.entries) {
      final value = parseAmount(field.text);
      final cat = _state.categories.where((c) => c.type == TxType.expense && c.name == name).firstOrNull;
      if (value == null || value <= 0 || cat == null) continue;
      await _state.api.saveBudget(cat.id, _state.monthKey, value, recurring: true);
      _budgetsCreated++;
    }
  }

  @override
  void dispose() {
    for (final c in [_wallet, ..._bankBalances.values, ..._budgets.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstName = (context.watch<AppState>().userName ?? '').trim().split(' ').first;
    final (bubble, content, primary, secondary) = switch (_step) {
      0 => (
          'Oi${firstName.isEmpty ? '' : ', $firstName'}! 🎉 Em 1 minutinho a gente deixa o Economizze com a sua cara. Bora?',
          const SizedBox.shrink(),
          ('Bora!', () => setState(() => _step++)),
          null,
        ),
      1 => (
          'Quanto dinheiro você tem na carteira agora? Só o dinheiro vivo, em espécie. 💵',
          _AmountField(controller: _wallet, label: 'Na carteira'),
          ('Continuar', () => _run(_saveWallet)),
          ('Não ando com dinheiro', () => setState(() => _step++)),
        ),
      2 => (
          'Em quais bancos você tem conta? Assim eu separo o saldo de cada um. 🏦',
          _banksStep(),
          ('Continuar', () => _run(_saveBanks)),
          ('Agora não', () => setState(() => _step++)),
        ),
      3 => (
          'Quanto você quer gastar por mês com cada coisa? Eu aviso antes de você estourar! 🎯',
          _budgetsStep(),
          ('Continuar', () => _run(_saveBudgets)),
          ('Deixo para depois', () => setState(() => _step++)),
        ),
      4 => (
          'Sabia que dá para anotar gastos pelo WhatsApp? Manda "gastei 30 no almoço", um áudio ou o print do PIX. 📱',
          const _WhatsAppArt(),
          (
            'Conectar agora',
            () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatsAppScreen()));
              if (mounted) setState(() => _step++);
            }
          ),
          ('Depois', () => setState(() => _step++)),
        ),
      _ => (
          'Tudo pronto! 🚀 Agora é só registrar seus gastos. Quanto mais você anota, melhor eu te ajudo a economizar.',
          _DoneSummary(accounts: _accountsCreated, budgets: _budgetsCreated),
          ('Começar a usar', () => _state.completeSetup()),
          null,
        ),
    };

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
            child: Row(children: [
              IconButton(
                tooltip: 'Pular configuração',
                icon: const Icon(Icons.close),
                onPressed: () => _state.completeSetup(),
              ),
              Expanded(child: ChunkyProgress(value: (_step + 1) / _steps)),
            ]),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween(begin: const Offset(.08, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: ListView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                children: [
                  if (_step == 0 || _step == _steps - 1) ...[
                    SpeechBubble(child: Text(bubble, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.4))),
                    const SizedBox(height: 4),
                    const Center(child: MascotAvatar(size: 170, bounce: true)),
                  ] else
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const MascotAvatar(size: 64),
                      Expanded(
                        child: SpeechBubble(
                          tailLeft: true,
                          child: Text(bubble, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4)),
                        ),
                      ),
                    ]),
                  const SizedBox(height: 24),
                  content,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(children: [
              ChunkyButton(label: primary.$1, onPressed: primary.$2, busy: _busy),
              SizedBox(
                height: 48,
                child: secondary == null
                    ? null
                    : TextButton(
                        onPressed: _busy ? null : secondary.$2,
                        child: Text(secondary.$1.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _banksStep() {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final b in _banks)
          FilterChip(
            avatar: CircleAvatar(backgroundColor: hexColor(b.color), radius: 9),
            label: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            selected: _selectedBanks.contains(b.name),
            onSelected: (on) => setState(() {
              if (on) {
                _selectedBanks.add(b.name);
                _bankBalances.putIfAbsent(b.name, TextEditingController.new);
              } else {
                _selectedBanks.remove(b.name);
              }
            }),
          ),
      ]),
      if (_selectedBanks.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Quanto tem em cada um? (pode deixar em branco)',
            style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final b in _banks.where((b) => _selectedBanks.contains(b.name)))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AmountField(
              controller: _bankBalances[b.name]!,
              label: b.name,
              icon: IconBadge(Icons.account_balance, hexColor(b.color), size: 32),
              compact: true,
            ),
          ),
      ],
    ]);
  }

  Widget _budgetsStep() {
    final categories = context.watch<AppState>().categories;
    return Column(children: [
      for (final name in _budgetCategories)
        if (categories.where((c) => c.type == TxType.expense && c.name == name).firstOrNull case final cat?)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AmountField(
              controller: _budgets[name]!,
              label: name,
              icon: IconBadge(categoryIcon(cat.icon), hexColor(cat.color), size: 32),
              compact: true,
            ),
          ),
      Text('Os limites se repetem todo mês. Dá para mudar quando quiser na aba Orçamentos.',
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Widget? icon;
  final bool compact;
  const _AmountField({required this.controller, required this.label, this.icon, this.compact = false});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(fontSize: compact ? 18 : 30, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          labelText: label,
          prefixText: 'R\$ ',
          hintText: '0,00',
          prefixIcon: icon == null ? null : Padding(padding: const EdgeInsets.all(10), child: icon),
        ),
      );
}

class _WhatsAppArt extends StatelessWidget {
  const _WhatsAppArt();

  @override
  Widget build(BuildContext context) {
    Widget msg(String text, {bool me = true}) => Align(
          alignment: me ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: me ? const Color(0xFFD9FDD3) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Text(text, style: const TextStyle(color: Color(0xFF1A1F1D), fontSize: 15)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFEFE7DE), borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        msg('gastei 32 no uber'),
        msg('✅ Despesa de R\$ 32,00 em Transporte — hoje, Carteira.', me: false),
        msg('🎤 recebi 2 mil do freela ontem'),
        msg('✅ Receita de R\$ 2.000,00 em Freelance — ontem.', me: false),
      ]),
    );
  }
}

class _DoneSummary extends StatelessWidget {
  final int accounts, budgets;
  const _DoneSummary({required this.accounts, required this.budgets});

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text) => ListTile(
          leading: IconBadge(icon, incomeColor, size: 40),
          title: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        );
    return Card(
      child: Column(children: [
        row(Icons.account_balance_wallet, accounts == 0 ? 'Carteira pronta' : 'Carteira e mais $accounts conta(s)'),
        row(Icons.savings, budgets == 0 ? 'Orçamentos: quando quiser' : '$budgets orçamento(s) definidos'),
        row(Icons.add_circle, 'Toque em "Lançar" para registrar o primeiro gasto'),
      ]),
    );
  }
}
