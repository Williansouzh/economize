import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/playful.dart';

const _icons = <String, IconData>{
  'flag': Icons.flag,
  'receipt_long': Icons.receipt_long,
  'local_fire_department': Icons.local_fire_department,
  'whatshot': Icons.whatshot,
  'savings': Icons.savings,
  'verified': Icons.verified,
  'trending_up': Icons.trending_up,
  'flag_circle': Icons.flag_circle,
  'emoji_events': Icons.emoji_events,
  'credit_card': Icons.credit_card,
};

const streakColor = Color(0xFFFF8A00);

/// Chip "🔥 5" do topo do Início: a sequência de dias registrando. Toque abre as conquistas.
class StreakChip extends StatelessWidget {
  const StreakChip({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return FutureBuilder<Progress>(
      key: ValueKey(state.revision),
      future: state.progress(),
      builder: (context, snap) {
        final p = snap.data;
        if (p == null) return const SizedBox.shrink();
        final active = p.registeredToday;
        return Tooltip(
          message: active ? 'Sequência de ${p.streak} dia(s)' : 'Registre algo hoje para manter a sequência',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (active ? streakColor : Colors.grey).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_fire_department, size: 20, color: active ? streakColor : Colors.grey),
                const SizedBox(width: 4),
                Text('${p.streak}',
                    style: TextStyle(fontWeight: FontWeight.w900, color: active ? streakColor : Colors.grey)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Sequência e conquistas, no estilo Duolingo.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Conquistas')),
      body: FutureBuilder<Progress>(
        key: ValueKey(state.revision),
        future: state.progress(),
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: state.dataChanged);
          final p = snap.data;
          if (p == null) return const Center(child: CircularProgressIndicator());
          final unlocked = p.achievements.where((a) => a.unlocked).length;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFB020), Color(0xFFFF6B00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(children: [
                const Icon(Icons.local_fire_department, color: Colors.white, size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.streak == 1 ? '1 dia seguido' : '${p.streak} dias seguidos',
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    Text(
                      p.registeredToday
                          ? 'Você já registrou hoje. Volte amanhã!'
                          : p.streak > 0
                              ? 'Registre algo hoje para não perder a sequência.'
                              : 'Registre um gasto hoje para começar.',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text('Recorde: ${p.bestStreak} ${p.bestStreak == 1 ? 'dia' : 'dias'}',
                        style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 12)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text('Conquistas', style: Theme.of(context).textTheme.titleLarge)),
              Text('$unlocked de ${p.achievements.length}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            ChunkyProgress(value: p.achievements.isEmpty ? 0 : unlocked / p.achievements.length),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: .95,
              children: [for (final a in p.achievements) _Badge(a)],
            ),
          ]);
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final Achievement a;
  const _Badge(this.a);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = a.unlocked ? const Color(0xFFFFB020) : cs.outline;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: a.unlocked ? .18 : .1),
              border: Border.all(color: color, width: 3),
            ),
            child: Icon(a.unlocked ? (_icons[a.icon] ?? Icons.star) : Icons.lock_outline, color: color, size: 30),
          ),
          const SizedBox(height: 10),
          Text(a.title,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, color: a.unlocked ? null : cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(a.description,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
