import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/app_icon.dart';
import '../services/bank_notifications.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'bank_notifications_screen.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';
import 'insights_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'transaction_form_screen.dart';
import 'transactions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;

  /// Abre uma aba de fora da barra (ex.: "Ajustar orçamento" na IA leva para Planejar).
  static void openTab(BuildContext context, int index) =>
      context.findAncestorStateOfType<HomeScreenState>()?._select(index);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Toque no aviso "gasto detectado" com o app aberto (MainActivity.onNewIntent).
    if (BankNotifications.supported) {
      const MethodChannel('economizze/bank_notifications').setMethodCallHandler((call) async {
        if (call.method == 'openDetected' && mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const BankNotificationsScreen()));
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Volta para o app: confere se o banco avisou alguma compra enquanto ele estava fechado.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) context.read<AppState>().refreshDetected();
    // Android: o ícone troca quando o app sai da frente (RN-49).
    if (s == AppLifecycleState.paused && AppIcon.changeOnPause) context.read<AppState>().applyPendingIcon();
  }

  // As abas só são montadas (e carregam dados) na primeira vez em que são abertas.
  final _visited = {0};

  static const _titles = ['Início', 'Lançamentos', 'IA', 'Planejar'];
  static const _pages = [DashboardScreen(), TransactionsScreen(), InsightsScreen(), BudgetsScreen()];

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Bom dia' : (h < 18 ? 'Boa tarde' : 'Boa noite');
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final name = (state.userName ?? '').trim();
    final firstName = name.split(' ').first;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: Text(_index == 0 ? (firstName.isEmpty ? _greeting : '$_greeting, $firstName') : _titles[_index]),
        actions: [
          if (_index == 0) const StreakPill(),
          if (_index == 1)
            IconButton(
              tooltip: 'Buscar',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              button: true,
              label: 'Perfil e ajustes',
              excludeSemantics: true,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: cs.primaryContainer,
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: 18)),
                ),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: [
        for (var i = 0; i < _pages.length; i++)
          _visited.contains(i) ? _FadeThroughTab(active: i == _index, child: _pages[i]) : const SizedBox.shrink(),
      ]),
      bottomNavigationBar: _BottomBar(index: _index, onSelect: _select),
    );
  }
}

/// Troca de aba no padrão fade-through do Material (210 ms, easeOutCubic): a aba que entra aparece
/// com fade e uma leve escala. Fica dentro do IndexedStack para cada aba manter a rolagem e o estado.
class _FadeThroughTab extends StatefulWidget {
  final bool active;
  final Widget child;
  const _FadeThroughTab({required this.active, required this.child});
  @override
  State<_FadeThroughTab> createState() => _FadeThroughTabState();
}

class _FadeThroughTabState extends State<_FadeThroughTab> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 210), value: 1);

  @override
  void didUpdateWidget(_FadeThroughTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeThroughTransition(
        animation: CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
        secondaryAnimation: kAlwaysDismissedAnimation,
        fillColor: Colors.transparent,
        child: widget.child,
      );
}

/// Barra inferior: Início · Lançamentos · [Lançar] · IA · Planejar. O Lançar fica no centro, em todas
/// as abas e sem cobrir conteúdo.
class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onSelect;
  const _BottomBar({required this.index, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget item(int i, IconData icon, IconData selectedIcon, String label) {
      final selected = i == index;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: () => onSelect(i),
          child: InkWell(
            onTap: () => onSelect(i),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 210),
                curve: Curves.easeOutCubic,
                width: selected ? 56 : 40,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? cs.primaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(selected ? selectedIcon : icon,
                    size: 24, color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? cs.onSurface : cs.onSurfaceVariant)),
            ]),
          ),
        ),
      );
    }

    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Container(
          height: 76,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            item(0, Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Início'),
            item(1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Lançamentos'),
            const Expanded(child: LaunchButton()),
            item(2, Icons.auto_awesome_outlined, Icons.auto_awesome, 'IA'),
            item(3, Icons.track_changes_outlined, Icons.track_changes_rounded, 'Planejar'),
          ]),
        ),
      ),
    );
  }
}

/// O botão "Lançar": moeda lima da marca. Ao tocar, cresce e vira a tela de lançamento
/// (container transform, 300 ms).
class LaunchButton extends StatelessWidget {
  const LaunchButton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: context.isDark ? null : brandShadow,
        ),
        child: OpenContainer(
          transitionDuration: const Duration(milliseconds: 300),
          transitionType: ContainerTransitionType.fadeThrough,
          closedColor: lima,
          openColor: bg,
          middleColor: bg,
          closedElevation: 0,
          openElevation: 0,
          closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          openBuilder: (_, _) => const TransactionFormScreen(),
          tappable: false,
          closedBuilder: (context, open) => Semantics(
            button: true,
            label: 'Lançar',
            excludeSemantics: true,
            onTap: open,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                HapticFeedback.lightImpact();
                open();
              },
              child: const SizedBox(width: 60, height: 44, child: Icon(Icons.add_rounded, color: tinta, size: 30)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      ExcludeSemantics(
        child: Text('Lançar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurface)),
      ),
    ]);
  }
}
