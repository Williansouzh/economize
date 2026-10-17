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
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (insights == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Icon(Icons.auto_awesome, size: 48, color: cs.primary),
                  const SizedBox(height: 8),
                  const Text('Deixe a IA analisar seus gastos do mês e sugerir onde economizar.',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _loading ? null : _generate,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.psychology),
                    label: Text(_loading ? 'Analisando...' : 'Gerar insights'),
                  ),
                ]),
              ),
            )
          else
            _InsightsView(insights, onRefresh: _loading ? null : _generate),
          const SizedBox(height: 16),
          Text('Pergunte à IA', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_chat.isEmpty)
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in const [
                'Onde estou gastando mais?',
                'Como economizar R\$ 500 por mês?',
                'Meus gastos estão saudáveis?',
              ])
                ActionChip(label: Text(s), onPressed: _asking ? null : () => _ask(s)),
            ]),
          for (final (role, text) in _chat)
            Align(
              alignment: role == 'user' ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxWidth: 320),
                decoration: BoxDecoration(
                  color: role == 'user' ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
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
                decoration: const InputDecoration(hintText: 'Ex.: posso gastar com uma viagem?', isDense: true),
                onSubmitted: (_) => _ask(),
              ),
            ),
            IconButton.filled(onPressed: _asking ? null : _ask, icon: const Icon(Icons.send)),
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
            ? Colors.orange
            : expenseColor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                    value: i.healthScore / 100, strokeWidth: 6, color: scoreColor, backgroundColor: scoreColor.withAlpha(40)),
                Text('${i.healthScore}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Saúde financeira', style: TextStyle(fontWeight: FontWeight.bold)),
                if (i.potentialSavings > 0)
                  Text('Economia possível: ${money(i.potentialSavings)}/mês',
                      style: const TextStyle(color: incomeColor)),
              ]),
            ),
            IconButton(onPressed: onRefresh, icon: const Icon(Icons.refresh), tooltip: 'Gerar novamente'),
          ]),
        ),
      ),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(i.summary))),
      if (i.alerts.isNotEmpty) _ListCard('Alertas', Icons.warning_amber, Colors.orange, i.alerts),
      if (i.tips.isNotEmpty) _ListCard('Dicas para economizar', Icons.lightbulb, incomeColor, i.tips),
    ]);
  }
}

class _ListCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> items;
  const _ListCard(this.title, this.icon, this.color, this.items);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            ...items.map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('•  '),
                    Expanded(child: Text(t)),
                  ]),
                )),
          ]),
        ),
      );
}
