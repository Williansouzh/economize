import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Insights gerados pelo DeepSeek (via backend) + chat "pergunte à IA".
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});
  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  Insights? _insights;
  String? _insightsMonth;
  bool _loading = false;

  final _question = TextEditingController();
  final _chat = <(String role, String text)>[];
  bool _asking = false;

  Future<void> _generate() async {
    final state = context.read<AppState>();
    setState(() => _loading = true);
    try {
      final r = await state.api.insights(state.monthKey);
      setState(() {
        _insights = r;
        _insightsMonth = state.monthKey;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _question.text).trim();
    if (q.isEmpty) return;
    final state = context.read<AppState>();
    setState(() {
      _chat.add(('user', q));
      _asking = true;
      _question.clear();
    });
    try {
      final answer = await state.api.ask(q, state.monthKey);
      setState(() => _chat.add(('ai', answer)));
    } catch (e) {
      setState(() => _chat.add(('ai', '⚠️ $e')));
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final insights = _insightsMonth == state.monthKey ? _insights : null;

    return Column(children: [
      const MonthSelector(),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
          if (insights == null)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6D5DF6), Color(0xFF3B82F6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.auto_awesome, size: 36, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  const Text('Análise do mês com IA',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('A IA lê seus gastos, dá uma nota para sua saúde financeira e mostra onde dá para economizar.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .85))),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white, foregroundColor: const Color(0xFF4F46E5)),
                    onPressed: _loading ? null : _generate,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.psychology),
                    label: Text(_loading ? 'Analisando...' : 'Gerar insights'),
                  ),
                ]),
            )
          else
            _InsightsView(insights, onRefresh: _loading ? null : _generate),
          const SizedBox(height: 12),
          const _PrivacyNote(),
          const SizedBox(height: 24),
          Row(children: [
            const IconBadge(Icons.forum_outlined, Color(0xFF6D5DF6), size: 34),
            const SizedBox(width: 10),
            Text('Pergunte à IA',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (_chat.isEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in const [
                'Onde estou gastando mais?',
                'Como economizar R\$ 500 por mês?',
                'Meus gastos estão saudáveis?',
              ])
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 16),
                  label: Text(s),
                  onPressed: _asking ? null : () => _ask(s),
                ),
            ]),
          for (final (role, text) in _chat)
            Align(
              alignment: role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: const BoxConstraints(maxWidth: 320),
                decoration: BoxDecoration(
                  color: role == 'user' ? cs.primary : Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(role == 'user' ? 18 : 4),
                    bottomRight: Radius.circular(role == 'user' ? 4 : 18),
                  ),
                ),
                child: Text(text, style: TextStyle(color: role == 'user' ? cs.onPrimary : null)),
              ),
            ),
          if (_asking) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _question,
                decoration: InputDecoration(
                  hintText: 'Ex.: posso gastar com uma viagem?',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: cs.outlineVariant)),
                ),
                onSubmitted: (_) => _ask(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _asking ? null : _ask,
              icon: const Icon(Icons.arrow_upward),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _InsightsView extends StatelessWidget {
  final Insights i;
  final VoidCallback? onRefresh;
  const _InsightsView(this.i, {this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scoreColor = i.healthScore >= 70
        ? incomeColor
        : i.healthScore >= 40
            ? warningColor
            : expenseColor;
    final scoreLabel = i.healthScore >= 70
        ? 'Muito bem!'
        : i.healthScore >= 40
            ? 'Dá para melhorar'
            : 'Atenção aos gastos';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(fit: StackFit.expand, children: [
                CircularProgressIndicator(
                  value: i.healthScore / 100,
                  strokeWidth: 9,
                  strokeCap: StrokeCap.round,
                  color: scoreColor,
                  backgroundColor: scoreColor.withValues(alpha: .14),
                ),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${i.healthScore}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
                    const Text('de 100', style: TextStyle(fontSize: 10)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Saúde financeira', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text(scoreLabel, style: TextStyle(color: scoreColor, fontWeight: FontWeight.w700)),
                if (i.potentialSavings > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: incomeColor.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Pode economizar ${money(i.potentialSavings)}/mês',
                        style: const TextStyle(color: incomeColor, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ],
              ]),
            ),
            IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh), tooltip: 'Gerar novamente'),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      _ListCard('Resumo', Icons.description_outlined, const Color(0xFF3B82F6), [i.summary], bullets: false),
      if (i.alerts.isNotEmpty) ...[
        const SizedBox(height: 12),
        _ListCard('Alertas', Icons.warning_amber_rounded, warningColor, i.alerts),
      ],
      if (i.tips.isNotEmpty) ...[
        const SizedBox(height: 12),
        _ListCard('Dicas para economizar', Icons.lightbulb_outline, incomeColor, i.tips),
      ],
    ]);
  }
}

class _ListCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;
  final bool bullets;
  const _ListCard(this.title, this.icon, this.color, this.items, {this.bullets = true});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(icon, color, size: 34),
              const SizedBox(width: 10),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            ...items.map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (bullets)
                      Container(
                        margin: const EdgeInsets.only(top: 7, right: 10),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                    Expanded(child: Text(t, style: const TextStyle(height: 1.4))),
                  ]),
                )),
          ]),
        ),
      );
}

/// O que sai do app para a IA (DeepSeek), para o usuário decidir antes de usar.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.shield_outlined, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Para analisar e responder, enviamos ao DeepSeek os totais do mês, os gastos por categoria, '
            'os orçamentos e as 10 maiores despesas com data e descrição. '
            'Seu nome, e-mail e os nomes das suas contas não são enviados.',
            style: TextStyle(fontSize: 12, height: 1.4, color: cs.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }
}
