import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';
import 'goals.dart';
import 'home_screen.dart';
import 'profiles_screen.dart';

/// IA em duas partes: Resumo do mês (nota, frase do Cofrinho, alertas e dicas com ação) e Conversa.
/// A privacidade fica numa linha com cadeado; o detalhe e o consentimento abrem numa folha.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _tab = 0;
  bool _loading = false;
  Object? _error;

  /// Lançamentos do mês (para "Preciso de 5 lançamentos"). Nulo até carregar.
  int? _entries;
  String? _entriesKey;

  final _question = TextEditingController();
  final _chat = <_Message>[];
  final _scroll = ScrollController();
  bool _asking = false;

  /// Perguntas que restam hoje (RN-48). Nulo até a primeira consulta.
  int? _remaining;
  static const maxQuestion = 300;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    final key = '${state.api.profileId}#${state.monthKey}#${state.revision}';
    if (key != _entriesKey) {
      _entriesKey = key;
      _loadEntries(state);
    }
  }

  Future<void> _loadEntries(AppState state) async {
    try {
      final (txs, _) = await state.monthEntries();
      if (!mounted) return;
      setState(() => _entries = txs.length);
      // Resumo pronto ao abrir: gerado uma vez por dia, em segundo plano (com consentimento).
      if (state.insightsFor(state.monthKey) == null) state.dailyInsights(entries: txs.length);
    } catch (_) {
      // Sem internet: o botão de gerar continua disponível.
    }
  }

  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadQuota() async {
    try {
      final r = await context.read<AppState>().api.chatRemaining();
      if (mounted) setState(() => _remaining = r);
    } catch (_) {
      // Sem internet ou IA desligada: o contador só aparece depois da primeira pergunta.
    }
  }

  /// No primeiro uso, mostra o que vai para a IA e pede o ok.
  Future<bool> _consent() async {
    final state = context.read<AppState>();
    if (state.aiConsentSeen) return true;
    final ok = await showAiPrivacySheet(context, consent: true);
    return ok == true;
  }

  Future<void> _generate() async {
    if (!await _consent() || !mounted) return;
    final state = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await state.api.insights(state.monthKey, includeDescriptions: state.sendDescriptionsToAi);
      state.keepInsights(state.monthKey, r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _question.text).trim();
    if (q.isEmpty || _remaining == 0) return;
    if (!await _consent() || !mounted) return;
    final state = context.read<AppState>();
    setState(() {
      _chat.add(_Message.user(q));
      _asking = true;
      _question.clear();
    });
    _scrollToEnd();
    try {
      final (answer, remaining) = await state.api.ask(q, state.monthKey, includeDescriptions: state.sendDescriptionsToAi);
      setState(() {
        _chat.add(_Message.ai(answer));
        _remaining = remaining ?? _remaining;
      });
    } on ApiException catch (e) {
      setState(() {
        if (e.status == 429) {
          _chat.add(_Message.ai('$e'));
          _remaining = 0;
        } else {
          _chat.add(_Message.error(q));
        }
      });
    } finally {
      if (mounted) setState(() => _asking = false);
      _scrollToEnd();
    }
  }

  void _retry(_Message failed) {
    setState(() {
      final i = _chat.indexOf(failed);
      // Tira a pergunta e o erro: a pergunta volta a ser enviada.
      if (i > 0) _chat.removeRange(i - 1, i + 1);
    });
    _ask(failed.question);
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
        }
      });

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(children: [
      MonthSelector(onTapLabel: () => showProfileSheet(context)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: PillSegments(labels: const ['Resumo do mês', 'Conversa'], selected: _tab, onChanged: (i) => setState(() => _tab = i)),
      ),
      const _PrivacyLine(),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 210),
          switchInCurve: Curves.easeOutCubic,
          child: _tab == 0
              ? _summary(state)
              : KeyedSubtree(key: const ValueKey('chat'), child: _conversation()),
        ),
      ),
      if (_tab == 1) _input(),
    ]);
  }

  Widget _summary(AppState state) {
    final insights = state.insightsFor(state.monthKey);
    final missing = _entries == null ? 0 : AppState.minEntriesForAi - _entries!;
    final Widget child;
    if (_loading) {
      child = const _Thinking();
    } else if (_error != null && insights == null) {
      child = _ErrorCard(onRetry: _generate, note: 'A análise não foi gerada e não contou no seu limite do dia.');
    } else if (insights == null) {
      child = _Intro(missing: missing, onGenerate: _generate);
    } else {
      child = _InsightsView(insights, onRefresh: _generate);
    }
    return ListView(
      key: const ValueKey('summary'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child)],
    );
  }

  Widget _conversation() {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Row(children: [
          Expanded(
            child: Text('Pergunte sobre o seu mês: eu respondo com os seus números.',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.35)),
          ),
          if (_remaining != null)
            Tooltip(
              message: 'Para não pesar no servidor, são 20 perguntas por dia. Zera à meia-noite.',
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  _remaining == 0 ? 'Acabou por hoje' : plural(_remaining!, 'pergunta hoje', 'perguntas hoje'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        if (_chat.isEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in const [
              'Onde estou gastando mais?',
              'Como economizar R\$ 500 por mês?',
              'Meus gastos estão saudáveis?',
              'Posso fazer uma viagem este ano?',
            ])
              ActionChip(
                label: Text(s),
                onPressed: _asking || _remaining == 0 ? null : () => _ask(s),
              ),
          ]),
        for (final m in _chat) _Bubble(m, onRetry: m.failed ? () => _retry(m) : null),
        if (_asking)
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                MascotAvatar(size: 36, pose: MascotPose.thinking),
                SizedBox(width: 8),
                Text('Pensando…', style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _input() {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _question,
              enabled: _remaining != 0,
              maxLength: maxQuestion,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                counterText: '',
                hintText: _remaining == 0 ? 'Amanhã tem mais perguntas 😊' : 'Pergunte sobre o seu mês…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cs.outlineVariant)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cs.primary, width: 2)),
              ),
              onSubmitted: (_) => _ask(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Enviar',
            onPressed: _asking || _remaining == 0 ? null : _ask,
            icon: const Icon(Icons.arrow_upward_rounded),
            style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
          ),
        ]),
      ),
    );
  }
}

class _Message {
  final String role, text;
  final String? question;
  bool get failed => question != null;
  _Message.user(this.text)
      : role = 'user',
        question = null;
  _Message.ai(this.text)
      : role = 'ai',
        question = null;
  _Message.error(String this.question)
      : role = 'ai',
        text = 'Não consegui responder agora.';
}

class _Bubble extends StatelessWidget {
  final _Message m;
  final VoidCallback? onRetry;
  const _Bubble(this.m, {this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = m.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: user ? (context.isDark ? cs.primaryContainer : mar) : cs.surface,
          border: user ? null : Border.all(color: m.failed ? context.colors.warning : cs.outlineVariant),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 4),
            bottomRight: Radius.circular(user ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.text,
              style: TextStyle(
                  height: 1.4,
                  fontWeight: m.failed ? FontWeight.w700 : null,
                  color: user ? (context.isDark ? cs.onPrimaryContainer : Colors.white) : null)),
          if (onRetry != null) ...[
            Text('Não contou como pergunta.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tentar de novo'),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Antes da primeira análise: o Cofrinho convida, ou diz quantos lançamentos faltam.
class _Intro extends StatelessWidget {
  final int missing;
  final VoidCallback onGenerate;
  const _Intro({required this.missing, required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = missing <= 0;
    return Card(
      key: const ValueKey('intro'),
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(children: [
          MascotAvatar(size: 88, pose: ready ? MascotPose.normal : MascotPose.sleeping),
          const SizedBox(height: 16),
          Text(ready ? 'Que tal uma análise do mês?' : 'Ainda é cedo para analisar',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            ready
                ? 'Eu olho seus gastos, dou uma nota e aponto onde dá para economizar. Leva uns segundos.'
                : 'Preciso de ${AppState.minEntriesForAi} lançamentos no mês para ter o que analisar — '
                    '${missing == 1 ? 'falta 1' : 'faltam $missing'}.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: ready ? onGenerate : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Gerar análise'),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Carregando: skeleton da nota com o Cofrinho pensando e frases que mudam.
class _Thinking extends StatefulWidget {
  const _Thinking();
  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> {
  static const _phrases = ['Somando seus gastos…', 'Comparando com o mês passado…', 'Procurando onde dá para economizar…'];
  int _i = 0;
  late final Timer _timer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
    if (mounted) setState(() => _i = (_i + 1) % _phrases.length);
  });

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(key: const ValueKey('thinking'), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Row(children: [
              const MascotAvatar(size: 80, pose: MascotPose.thinking),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(_phrases[_i],
                        key: ValueKey(_i), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  const Skeleton(width: 140, height: 14),
                  const SizedBox(height: 8),
                  const Skeleton(width: 100, height: 14),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(Space.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(width: 180, height: 16),
              SizedBox(height: 12),
              Skeleton(height: 14),
              SizedBox(height: 8),
              Skeleton(height: 14),
              SizedBox(height: 8),
              Skeleton(width: 220, height: 14),
            ]),
          ),
        ),
      ]);
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;
  final String note;
  const _ErrorCard({required this.onRetry, required this.note});

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('error'),
        child: Padding(
          padding: const EdgeInsets.all(Space.xxl),
          child: Column(children: [
            const MascotAvatar(size: 80, pose: MascotPose.worried),
            const SizedBox(height: 16),
            Text('Não consegui falar com a IA agora', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(note, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Tentar de novo')),
          ]),
        ),
      );
}

class _InsightsView extends StatelessWidget {
  final Insights i;
  final VoidCallback onRefresh;
  const _InsightsView(this.i, {required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cs = Theme.of(context).colorScheme;
    final scoreColor = i.healthScore >= 70 ? colors.success : (i.healthScore >= 40 ? colors.warning : colors.expense);
    final scoreLabel = i.healthScore >= 70 ? 'Muito bem' : (i.healthScore >= 40 ? 'Dá para melhorar' : 'Atenção aos gastos');
    final now = DateTime.now();
    final g = i.generatedAt;
    final when = g.year == now.year && g.month == now.month && g.day == now.day
        ? 'hoje, ${DateFormat('HH:mm').format(g)}'
        : DateFormat("d 'de' MMM, HH:mm", 'pt_BR').format(g);
    return Column(key: const ValueKey('insights'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Row(children: [
            SizedBox(
              width: 84,
              height: 84,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: i.healthScore / 100),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Stack(fit: StackFit.expand, children: [
                  CircularProgressIndicator(
                    value: v,
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    color: scoreColor,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                  Center(child: Text('${i.healthScore}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 26))),
                ]),
              ),
            ),
            const SizedBox(width: Space.xl),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Saúde financeira', style: Theme.of(context).textTheme.bodySmall),
                Text(scoreLabel, style: Theme.of(context).textTheme.titleLarge),
                if (i.potentialSavings > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
                    child: Text('Dá para guardar +${perMonth(i.potentialSavings)}',
                        style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const MascotAvatar(size: 32),
              const SizedBox(width: 8),
              Expanded(child: Text('Cofrinho · atualizado $when', style: Theme.of(context).textTheme.bodySmall)),
              IconButton(
                tooltip: i.cached ? 'Seus dados não mudaram: é a mesma análise' : 'Gerar de novo',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ]),
            const SizedBox(height: 8),
            Text(i.summary, style: const TextStyle(fontSize: 16, height: 1.45, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
      if (i.alerts.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(Space.xl),
          decoration: BoxDecoration(color: colors.warningSoft, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: colors.onWarningSoft),
              const SizedBox(width: 8),
              Text('Atenção', style: TextStyle(fontWeight: FontWeight.w800, color: colors.onWarningSoft)),
            ]),
            for (final a in i.alerts)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(a, style: const TextStyle(height: 1.4))),
          ]),
        ),
      ],
      if (i.tips.isNotEmpty) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dá para fazer', style: Theme.of(context).textTheme.titleMedium),
              for (final t in i.tips) _Tip(t),
            ]),
          ),
        ),
      ],
    ]);
  }
}

/// Dica com a ação ao lado: "Ajustar orçamento" (corte de gasto) ou "Guardar na meta" (guardar dinheiro).
class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) {
    final t = text.toLowerCase();
    final cs = Theme.of(context).colorScheme;
    final (String, VoidCallback)? action = RegExp(r'separe|guard|reserva|meta|poup|invist').hasMatch(t)
        ? ('Guardar na meta', () => showGoalSheet(context))
        : RegExp(r'cort|reduz|limite|orçamento|orcamento|gast|evite|troc').hasMatch(t)
            ? ('Ajustar orçamento', () => HomeScreenState.openTab(context, 3))
            : null;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 7, right: 12),
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: const TextStyle(height: 1.4)),
            if (action != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                onPressed: action.$2,
                child: Text(action.$1, style: const TextStyle(fontSize: 14)),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Linha "🔒 Seu nome e suas contas não saem do app. O que a IA vê".
class _PrivacyLine extends StatelessWidget {
  const _PrivacyLine();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(children: [
        Icon(Icons.lock_outline_rounded, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Nome e contas não saem do app.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        ),
        TextButton(onPressed: () => showAiPrivacySheet(context), child: const Text('O que a IA vê')),
      ]),
    );
  }
}

/// O que sai do app para a IA (DeepSeek) e a escolha de enviar as descrições. Com [consent], é a
/// folha do primeiro uso: devolve true se a pessoa concordou.
Future<bool?> showAiPrivacySheet(BuildContext context, {bool consent = false}) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) {
        final state = c.watch<AppState>();
        final cs = Theme.of(c).colorScheme;
        final withDescriptions = state.sendDescriptionsToAi;
        Widget item(IconData icon, String text) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
              ]),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(consent ? 'Antes de usar a IA' : 'O que a IA vê', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Para analisar e responder, o app manda para a IA (DeepSeek):',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              item(Icons.bar_chart_rounded, 'Os totais do mês, os gastos por categoria e os orçamentos.'),
              item(Icons.receipt_long_outlined,
                  'As 10 maiores despesas ${withDescriptions ? 'com data e descrição' : 'só com data, categoria e valor'}.'),
              item(Icons.person_outline_rounded, 'Idade, estado e fontes de renda do questionário.'),
              item(Icons.lock_outline_rounded, 'Nunca vão: seu nome, e-mail e os nomes das suas contas.'),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('ai-descriptions'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enviar as descrições das despesas'),
                subtitle: Text(withDescriptions
                    ? 'Ex.: "Consulta Dr. Silva". Deixa as dicas mais precisas.'
                    : 'Desligado: a IA não vê as descrições.'),
                value: withDescriptions,
                onChanged: state.setSendDescriptionsToAi,
              ),
              TextButton(
                onPressed: () => launchUrl(Uri.parse(privacyPolicyUrl), mode: LaunchMode.externalApplication),
                child: const Text('Ler a política de privacidade'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  if (!state.aiConsentSeen) state.acceptAiConsent();
                  Navigator.pop(c, true);
                },
                child: Text(consent ? 'Entendi, pode usar' : 'Pronto'),
              ),
              if (consent)
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
            ]),
          ),
        );
      },
    );
