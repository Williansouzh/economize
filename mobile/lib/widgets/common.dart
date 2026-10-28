import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'playful.dart';

/// Seletor "‹ Outubro 2026 · Pessoal ›" do topo das telas. Com perfil de empresa, o nome do perfil
/// aparece junto e o toque no meio abre a troca de perfil.
class MonthSelector extends StatelessWidget {
  final VoidCallback? onTapLabel;
  const MonthSelector({super.key, this.onTapLabel});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final text = Theme.of(context).textTheme;
    final profile = state.profiles.length > 1 ? state.activeProfile : null;
    final label = profile == null
        ? monthLabel(state.month)
        : '${monthLabel(state.month)} · ${profile.isBusiness ? profile.name : 'Pessoal'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(children: [
        IconButton(
          tooltip: 'Mês anterior',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => state.changeMonth(-1),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTapLabel,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  label,
                  key: ValueKey(label),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Próximo mês',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => state.changeMonth(1),
        ),
      ]),
    );
  }
}

/// Ícone na cor da categoria sobre um círculo tingido (≥ 3,5:1). [solid]: círculo cheio, para seleção.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final bool solid;
  const IconBadge(this.icon, this.color, {super.key, this.size = 40, this.solid = false});

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: dark ? .2 : .13),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: solid ? onColor(color) : color, size: size * .5),
    );
  }
}

/// Título de seção (16/800) com ação opcional à direita. Seções ficam a 32 uma da outra.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  final EdgeInsetsGeometry padding;
  const SectionHeader(this.title, {super.key, this.action, this.padding = const EdgeInsets.fromLTRB(4, 0, 0, 8)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?action,
        ]),
      );
}

/// Cartão com título (e ação opcional à direita) usado para agrupar conteúdo.
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
    this.padding = const EdgeInsets.all(Space.xl),
  });

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ?action,
            ]),
            const SizedBox(height: Space.md),
            child,
          ]),
        ),
      );
}

/// Selo em caixa alta (12/800, +0,5): a única caixa alta do app.
class StatusBadge extends StatelessWidget {
  final String text;
  final Color background, foreground;
  final IconData? icon;
  const StatusBadge(this.text, {super.key, required this.background, required this.foreground, this.icon});

  /// Selo de atenção ("pendente", "atenção") nas cores semânticas do tema.
  factory StatusBadge.warning(BuildContext context, String text, {IconData? icon}) =>
      StatusBadge(text, background: context.colors.warningSoft, foreground: context.colors.onWarningSoft, icon: icon);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: foreground), const SizedBox(width: 4)],
          Text(text.toUpperCase(),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .5, color: foreground)),
        ]),
      );
}

/// Barra de progresso de 8 dp com cor de status e, opcionalmente, o marcador de "onde você deveria
/// estar hoje" (ex.: dia 28 de 31 = 90%). Cresce de 0 na primeira vez que aparece.
class StatusBar extends StatelessWidget {
  final double value;
  final Color color;
  final double? marker;
  final double height;
  const StatusBar({super.key, required this.value, required this.color, this.marker, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: height + 6,
        child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
          Container(
            height: height,
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(height)),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: w * v,
              height: height,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height)),
            ),
          ),
          if (marker != null)
            Positioned(
              left: (w * marker!.clamp(0, 1) - 1).clamp(0, w - 2),
              child: Container(width: 2, height: height + 6, color: cs.onSurface.withValues(alpha: .55)),
            ),
        ]),
      );
    });
  }
}

/// Seletor de cor com as 10 cores da paleta (categoria, conta e meta).
class PaletteColorPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const PaletteColorPicker({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = context.isDark;
    final current = paletteColor(selected).toARGB32();
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final (light, _, name) in categoryPalette)
        Semantics(
          label: name,
          selected: hexColor(light).toARGB32() == current,
          button: true,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(light);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: paletteColor(light, dark: dark),
                shape: BoxShape.circle,
                border: Border.all(
                  color: hexColor(light).toARGB32() == current ? cs.onSurface : Colors.transparent,
                  width: 3,
                ),
              ),
              child: hexColor(light).toARGB32() == current
                  ? Icon(Icons.check_rounded, size: 20, color: onColor(paletteColor(light, dark: dark)))
                  : null,
            ),
          ),
        ),
    ]);
  }
}

/// Bloco cinza pulsando no lugar do conteúdo que ainda está carregando (skeleton).
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const Skeleton({super.key, this.width, this.height = 16, this.radius = 8});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final a = cs.surfaceContainerHighest, b = cs.surfaceContainerLow;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(a, b, Curves.easeInOut.transform(_c.value)),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Estado vazio: o Cofrinho dormindo (ou um ícone), um título e o próximo passo.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  /// Mostra o Cofrinho dormindo no lugar do ícone.
  final bool mascot;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.mascot = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(children: [
        if (mascot)
          const MascotAvatar(size: 88, pose: MascotPose.sleeping)
        else
          IconBadge(icon, cs.primary, size: 72),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, height: 1.4)),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
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
            IconBadge(Icons.cloud_off_rounded, context.colors.expense, size: 72),
            const SizedBox(height: 16),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tentar de novo'),
            ),
          ]),
        ),
      );
}

void showError(BuildContext context, Object e) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));

/// Folha de baixo para criar ou editar (raio 28). O conteúdo rola e sobe com o teclado.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder}) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: builder(c),
          ),
        ),
      ),
    );

/// Título de folha (20/800) com ação opcional à direita (ex.: excluir).
class SheetTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SheetTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
          ?trailing,
        ]),
      );
}

/// Linha clicável de uma lista agrupada (Perfil, ajustes): 64 de altura, ícone 40, chevron.
class NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  const NavRow({super.key, required this.icon, required this.title, this.value, this.onTap, this.color, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 22, color: color ?? cs.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Text(title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color ?? cs.onSurface)),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(value!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
              ),
            trailing ?? Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// Grupo de [NavRow] num cartão, com divisórias e um título pequeno em cima.
class NavGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const NavGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(title!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
        ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 54),
            c,
          ],
        ]),
      ),
    ]);
  }
}

/// Segmento em pílula (ex.: "Resumo · Conversa", "Orçamentos · Metas"): selecionado em primaryContainer.
class PillSegments extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  const PillSegments({super.key, required this.labels, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        for (final (i, label) in labels.indexed)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == selected,
              child: GestureDetector(
                onTap: () {
                  if (i == selected) return;
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? cs.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: i == selected && !context.isDark
                        ? const [BoxShadow(color: Color(0x140B2B2E), blurRadius: 6, offset: Offset(0, 2))]
                        : null,
                  ),
                  child: Text(label,
                      style: TextStyle(
                        fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                        color: i == selected ? cs.onSurface : cs.onSurfaceVariant,
                      )),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
