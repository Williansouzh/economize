import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Painel do super admin (RN-44): quantas pessoas se cadastraram e quantas estão usando o app.
/// "Ativo" é quem abriu o app ou falou com o WhatsApp no dia.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<AdminStats> _future = _load();

  Future<AdminStats> _load() => context.read<AppState>().api.adminStats();

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Painel do admin')),
    body: FutureBuilder<AdminStats>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _refresh);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final s = snap.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Hero(stats: s),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Metric('Ativos hoje', s.activeToday, Icons.bolt, warningColor),
                  const SizedBox(width: 12),
                  _Metric('Ativos em 7 dias', s.active7Days, Icons.today, _blue),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Metric('Ativos em 30 dias', s.active30Days, Icons.calendar_month, incomeColor),
                  const SizedBox(width: 12),
                  _Metric('Com WhatsApp', s.whatsAppLinked, Icons.chat, const Color(0xFF25D366)),
                ],
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Últimos 30 dias',
                child: _DaysChart(days: s.days),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Cadastros recentes',
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(children: [for (final u in s.recentUsers) _UserTile(u)]),
              ),
            ],
          ),
        );
      },
    ),
  );
}

const _blue = Color(0xFF3B82F6);

class _Hero extends StatelessWidget {
  final AdminStats stats;
  const _Hero({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.black, .25)!]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pessoas cadastradas',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
          Text(
            NumberFormat.decimalPattern('pt_BR').format(stats.totalUsers),
            style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900, height: 1.1),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('+${stats.newToday} hoje'),
              chip('+${stats.new7Days} em 7 dias'),
              chip('+${stats.new30Days} em 30 dias'),
              chip('${NumberFormat.decimalPattern('pt_BR').format(stats.transactions30Days)} lançamentos em 30 dias'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _Metric(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconBadge(icon, color, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Barras de ativos por dia, com os cadastros do dia em destaque na base de cada barra.
class _DaysChart extends StatelessWidget {
  final List<AdminDay> days;
  const _DaysChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = days.fold<int>(1, (m, d) => d.active > m ? d.active : (d.signups > m ? d.signups : m));
    final df = DateFormat('d/M', 'pt_BR');
    Widget legend(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in days)
                Expanded(
                  child: Tooltip(
                    message: '${df.format(d.day)}: ${d.active} ativos, ${d.signups} cadastros',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            height: 4 + 116 * d.active / top,
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: .35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          if (d.signups > 0)
                            Container(
                              height: 4 + 116 * d.signups / top,
                              decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(3)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(df.format(days.first.day), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            Text('hoje', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          children: [legend(cs.primary.withValues(alpha: .35), 'Ativos'), legend(cs.primary, 'Cadastros')],
        ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  final AdminUser user;
  const _UserTile(this.user);

  static String _ago(DateTime? t) {
    if (t == null) return 'nunca voltou';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 10) return 'agora';
    if (d.inHours < 1) return 'há ${d.inMinutes} min';
    if (d.inDays < 1) return 'há ${d.inHours} h';
    if (d.inDays == 1) return 'ontem';
    return 'há ${d.inDays} dias';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = user.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Text(
          initials,
          style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              user.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (user.whatsApp) ...[const SizedBox(width: 6), const Icon(Icons.chat, size: 14, color: Color(0xFF25D366))],
        ],
      ),
      subtitle: Text(
        '${user.email}\nEntrou ${DateFormat("d 'de' MMM", 'pt_BR').format(user.createdAt)} · '
        '${user.transactions} lançamentos · ${_ago(user.lastSeenAt)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
    );
  }
}
