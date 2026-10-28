import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/about_fields.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'transaction_form_screen.dart';
import 'whatsapp_screen.dart';

/// Configuração guiada logo depois de criar a conta, em 5 passos: (1) idade e estado, (2) renda e
/// objetivo (RN-46), (3) contas com saldo, (4) WhatsApp (opcional) e (5) o primeiro gasto, com o
/// mesmo teclado do lançamento. Perfil de empresa, orçamentos e o comparativo ficam para depois
/// (checklist do Início e "Seu mês"). Cada passo salva ao continuar: dá para fechar no meio.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _Bank {
  final String name, color;
  const _Bank(this.name, this.color);
}

// A cor do banco fica salva na conta (é como a pessoa reconhece); na tela ela aparece só no ícone.
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

class _SetupScreenState extends State<SetupScreen> {
  static const _steps = 5;
  int _step = 0;
  bool _busy = false;
  bool _back = false;

  final _about = AboutDraft();
  final _wallet = TextEditingController();
  final _selectedBanks = <String>{};
  final _bankBalances = <String, TextEditingController>{};

  AppState get _state => context.read<AppState>();

  void _go(int step) {
    HapticFeedback.selectionClick();
    setState(() {
      _back = step < _step;
      _step = step;
    });
  }

  Future<void> _run(Future<void> Function() save) async {
    setState(() => _busy = true);
    try {
      await save();
      _state.dataChanged();
      if (mounted) _go(_step + 1);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAbout() async {
    if (!await confirmLowIncome(context, _about) || !mounted) return;
    await _run(() => _state.saveAbout(
          birthYear: _about.validYear ? _about.year : null,
          state: _about.state,
          sources: _about.sources.toList(),
          jobCount: _about.jobCount,
          monthlyIncome: _about.monthlyIncome,
          mainGoal: _about.goal,
        ));
  }

  Future<void> _saveAccounts() async {
    final value = parseAmount(_wallet.text) ?? 0;
    final wallet = _state.accounts.where((a) => a.name == 'Carteira').firstOrNull ?? _state.accounts.firstOrNull;
    if (wallet != null && value != wallet.initialBalance) {
      await _state.api.saveAccount(
          id: wallet.id, name: wallet.name, initialBalance: value, color: wallet.color, icon: wallet.icon);
    }
    final existing = _state.accounts.map((a) => a.name.toLowerCase()).toSet();
    for (final bank in _banks.where((b) => _selectedBanks.contains(b.name))) {
      if (existing.contains(bank.name.toLowerCase())) continue;
      await _state.api.saveAccount(
        name: bank.name,
        initialBalance: parseAmount(_bankBalances[bank.name]?.text ?? '') ?? 0,
        color: bank.color,
        icon: 'account_balance',
      );
    }
  }

  @override
  void dispose() {
    for (final c in [_wallet, ..._bankBalances.values]) {
      c.dispose();
    }
    _about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstName = (context.watch<AppState>().userName ?? '').trim().split(' ').first;
    void changed() => setState(() {});
    final hi = firstName.isEmpty ? 'Oi!' : 'Oi, $firstName!';

    final (bubble, content, primary, secondary) = switch (_step) {
      0 => (
          '$hi 🎉 Em 2 minutinhos o Economizze fica com a sua cara. Primeiro: em que ano você nasceu e onde mora?',
          AgeFields(_about, onChanged: changed),
          ('Continuar', _about.validYear ? () => _go(1) : null),
          ('Prefiro não dizer', () => _go(1)),
        ),
      1 => (
          'De onde vem o seu dinheiro, quanto entra por mês e o que você mais quer agora? 🎯',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SourcesFields(_about, onChanged: changed),
            const SizedBox(height: Space.xxl),
            IncomeGoalFields(_about, onChanged: changed),
          ]),
          ('Continuar', _saveAbout),
          ('Pular', () => _run(() async {})),
        ),
      2 => (
          'Onde está o seu dinheiro hoje? Assim eu separo o saldo de cada lugar. 🏦',
          _accountsStep(),
          ('Continuar', () => _run(_saveAccounts)),
          ('Agora não', () => _go(3)),
        ),
      3 => (
          'Dá para anotar gastos pelo WhatsApp: "gastei 30 no almoço", um áudio ou o print do Pix. 📱',
          const _WhatsAppArt(),
          (
            'Conectar o WhatsApp',
            () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const WhatsAppScreen()));
              if (mounted) _go(4);
            }
          ),
          ('Depois', () => _go(4)),
        ),
      _ => ('Por último: qual foi o seu último gasto? Pode ser o café de hoje. ☕', const SizedBox.shrink(), null, null),
    };

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
      child: Row(children: [
        IconButton(
          tooltip: _step == 0 ? 'Pular configuração' : 'Voltar',
          icon: Icon(_step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: () => _step == 0 ? _state.completeSetup() : _go(_step - 1),
        ),
        Expanded(child: ChunkyProgress(value: (_step + 1) / _steps)),
        const SizedBox(width: 12),
        Text('${_step + 1} de $_steps', style: Theme.of(context).textTheme.bodySmall),
        if (_step == _steps - 1)
          TextButton(onPressed: () => _state.completeSetup(), child: const Text('Pular')),
        const SizedBox(width: 8),
      ]),
    );

    final speech = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MascotAvatar(size: 64, pose: _step == 0 ? MascotPose.waving : (_step == 3 ? MascotPose.phone : MascotPose.normal)),
      Expanded(
        child: SpeechBubble(
          tailLeft: true,
          child: Text(bubble, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.4)),
        ),
      ),
    ]);

    final Widget page;
    if (_step == _steps - 1) {
      // O primeiro gasto com o teclado do lançamento: o Início já abre com ele e a conquista.
      page = Column(key: const ValueKey('first'), children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: speech),
        Expanded(
          child: TransactionFormScreen(
            prompt: 'Quanto foi?',
            onSaved: () async {
              HapticFeedback.heavyImpact();
              await showModalBottomSheet(
                context: context,
                builder: (c) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const MascotAvatar(size: 120, pose: MascotPose.celebrating, bounce: true),
                      const SizedBox(height: 16),
                      Text('Primeiro passo! 🎉', style: Theme.of(c).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text('Tudo pronto. Quanto mais você anota, melhor eu te ajudo a economizar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant, height: 1.4)),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Começar a usar')),
                      ),
                    ]),
                  ),
                ),
              );
              _state.completeSetup();
            },
          ),
        ),
      ]);
    } else {
      // Conteúdo ancorado perto do botão: sem buracos de 400 px entre a pergunta e o Continuar.
      page = LayoutBuilder(
        key: ValueKey(_step),
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight - 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [speech, const SizedBox(height: Space.xxl), content],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          header,
          Expanded(
            child: PageTransitionSwitcher(
              duration: const Duration(milliseconds: 300),
              reverse: _back,
              transitionBuilder: (child, a, b) => SharedAxisTransition(
                animation: a,
                secondaryAnimation: b,
                transitionType: SharedAxisTransitionType.horizontal,
                fillColor: Colors.transparent,
                child: child,
              ),
              child: page,
            ),
          ),
          if (primary != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(children: [
                ChunkyButton(label: primary.$1, onPressed: primary.$2, busy: _busy),
                SizedBox(
                  height: 48,
                  child: secondary == null
                      ? null
                      : TextButton(onPressed: _busy ? null : secondary.$2, child: Text(secondary.$1)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _accountsStep() {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _AmountField(
        controller: _wallet,
        label: 'Dinheiro vivo, na carteira',
        icon: IconBadge(Icons.account_balance_wallet_rounded, cs.primary, size: 32),
      ),
      const SizedBox(height: Space.xl),
      Text('Bancos', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: Space.sm),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final b in _banks)
          FilterChip(
            // Bolinha do banco só quando não está marcado: marcado mostra o check (sem desenhar um sobre o outro).
            avatar: _selectedBanks.contains(b.name)
                ? null
                : CircleAvatar(backgroundColor: tintOf(context, b.color), radius: 8),
            label: Text(b.name),
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
        const SizedBox(height: Space.lg),
        Text('Quanto tem em cada um? Pode deixar em branco.', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final b in _banks.where((b) => _selectedBanks.contains(b.name)))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AmountField(
              controller: _bankBalances[b.name]!,
              label: b.name,
              icon: IconBadge(Icons.account_balance_rounded, tintOf(context, b.color), size: 32),
            ),
          ),
      ],
    ]);
  }
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Widget? icon;
  const _AmountField({required this.controller, required this.label, this.icon});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [MoneyInputFormatter()],
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
    final cs = Theme.of(context).colorScheme;
    Widget msg(String text, {bool me = true}) => Align(
          alignment: me ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: me ? cs.primaryContainer : cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: me ? null : Border.all(color: cs.outlineVariant),
            ),
            child: Text(text, style: TextStyle(fontSize: 15, color: me ? cs.onPrimaryContainer : cs.onSurface)),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          msg('gastei 32 no uber'),
          msg('✅ Despesa de R\$ 32,00 em Transporte, hoje.', me: false),
          msg('🎤 recebi 2 mil do freela ontem'),
          msg('✅ Receita de R\$ 2.000,00 em Freelance, ontem.', me: false),
        ]),
      ),
    );
  }
}
