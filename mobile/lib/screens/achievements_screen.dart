import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
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
          return ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom), children: [
            // Sequência em tinta com a chama lima (a cor da marca, não um laranja avulso).
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: tinta,
                border: context.isDark ? Border.all(color: context.colors.cardBorder) : null,
              ),
              child: Row(children: [
                Icon(p.registeredToday ? Icons.local_fire_department_rounded : Icons.local_fire_department_outlined,
                    color: lima, size: 64),
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
            const SizedBox(height: 12),
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
              childAspectRatio: .86,
              children: [for (final a in p.achievements) _Badge(a)],
            ),
          ]);
        },
      ),
    );
  }
}

/// Conquista: as feitas em lima com o Cofrinho comemorando; as que faltam com um anel de progresso
/// em mar ("3 de 7 dias"), para dar vontade de completar.
class _Badge extends StatelessWidget {
  final Achievement a;
  const _Badge(this.a);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = a.progress;
    final ring = context.isDark ? lima : mar;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: 68,
            height: 68,
            child: a.unlocked
                ? Container(
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: lima),
                    child: Icon(_icons[a.icon] ?? Icons.star_rounded, color: tinta, size: 32),
                  )
                : Stack(fit: StackFit.expand, children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress ?? 0),
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => CircularProgressIndicator(
                        value: v,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        color: ring,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    ),
                    Icon(_icons[a.icon] ?? Icons.star_rounded, color: cs.onSurfaceVariant, size: 28),
                  ]),
          ),
          const SizedBox(height: 10),
          Text(a.title,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, color: a.unlocked ? null : cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            !a.unlocked && a.current != null && a.target != null ? '${a.current} de ${a.target} · ${a.description}' : a.description,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}
