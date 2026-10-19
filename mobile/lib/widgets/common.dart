import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/format.dart';

/// Seletor "‹ Outubro 2026 ›" usado no topo das telas.
class MonthSelector extends StatelessWidget {
  const MonthSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => state.changeMonth(-1)),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.calendar_month, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(monthLabel(state.month),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => state.changeMonth(1)),
        ]),
      ),
    );
  }
}

/// Ícone dentro de um quadrado arredondado com fundo na cor do ícone, bem clarinho.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool solid;
  const IconBadge(this.icon, this.color, {super.key, this.size = 44, this.solid = false});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: solid ? color : color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(size * .32),
        ),
        child: Icon(icon, color: solid ? onColor(color) : color, size: size * .52),
      );
}

/// Card branco com título (e ação opcional à direita) usado para agrupar conteúdo.
class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  final EdgeInsetsGeometry padding;
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.action,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              ?action,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(children: [
        IconBadge(icon, cs.primary, size: 72),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ]),
    );
  }
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const IconBadge(Icons.cloud_off, expenseColor, size: 72),
            const SizedBox(height: 16),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ]),
        ),
      );
}

void showError(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
