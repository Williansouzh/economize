import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/app_icon.dart';
import '../services/bank_notifications.dart';
import '../services/reminders.dart';
import '../state/app_state.dart';
import '../utils/save_file.dart';
import '../widgets/common.dart';
import 'achievements_screen.dart';
import 'admin_screen.dart';
import 'analysis_screen.dart';
import 'bank_notifications_screen.dart';
import 'budgets_screen.dart';
import 'categories_screen.dart';
import 'dashboard_screen.dart';
import 'delete_account_screen.dart';
import 'import_screen.dart';
import 'profiles_screen.dart';
import 'insights_screen.dart';
import 'reminders_screen.dart';
import 'search_screen.dart';
import 'transaction_form_screen.dart';
import 'transactions_screen.dart';
import 'whatsapp_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;

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

  static const _titles = ['Visão geral', 'Lançamentos', 'Insights IA', 'Planejamento'];
  static const _pages = [DashboardScreen(), TransactionsScreen(), InsightsScreen(), BudgetsScreen()];

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Bom dia' : (h < 18 ? 'Boa tarde' : 'Boa noite');
  }

  Future<void> _logoutEverywhere() async {
    final state = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.devices_outlined),
        title: const Text('Sair de todos os aparelhos?'),
        content: const Text(
            'Sua conta será desconectada em todos os celulares e navegadores, inclusive neste. '
            'Use se perdeu um aparelho ou entrou em um computador de outra pessoa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sair de todos')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await state.logoutEverywhere();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _export() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Gerando a planilha...')));
    try {
      final bytes = await state.api.exportCsv();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await saveFile(bytes, 'economizze-$today.csv', 'text/csv');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final name = (state.userName ?? '').trim();
    final firstName = name.split(' ').first;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: _index == 0
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$_greeting${firstName.isEmpty ? '' : ','}',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
                Text(firstName.isEmpty ? 'Economizze' : firstName),
              ])
            : Text(_titles[_index]),
        actions: [
          // Com um perfil de empresa, o seletor fica no topo de todas as abas (RN-47).
          if (state.profiles.length > 1) const ProfileSwitcher() else if (_index == 0) const StreakChip(),
          if (_index == 1)
            IconButton(
              tooltip: 'Buscar',
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
            ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PopupMenuButton<String>(
              tooltip: 'Conta',
              position: PopupMenuPosition.under,
              onSelected: (v) => switch (v) {
                'logout' => state.logout(),
                'logout_all' => _logoutEverywhere(),
                'whatsapp' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const WhatsAppScreen())),
                'situation' => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalysisScreen())),
                'about' => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
                'profiles' => showProfileSheet(context),
                'icon' => state.setDynamicIcon(!state.dynamicIcon),
                'categories' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
                'achievements' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const AchievementsScreen())),
                'reminders' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const RemindersScreen())),
                'export' => _export(),
                'admin' => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                'import' => Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen())),
                'bank' => Navigator.push(context, MaterialPageRoute(builder: (_) => const BankNotificationsScreen())),
                'privacy' => launchUrl(Uri.parse(privacyPolicyUrl), mode: LaunchMode.externalApplication),
                'reset' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const DeleteAccountScreen(resetOnly: true))),
                'delete' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text(name.isEmpty ? 'Minha conta' : name)),
                const PopupMenuDivider(),
                if (state.isAdmin)
                  const PopupMenuItem(
                    value: 'admin',
                    child: ListTile(leading: Icon(Icons.insights_outlined), title: Text('Painel do admin')),
                  ),
                const PopupMenuItem(
                  value: 'situation',
                  child: ListTile(leading: Icon(Icons.monitor_heart_outlined), title: Text('Minha situação')),
                ),
                const PopupMenuItem(
                  value: 'about',
                  child: ListTile(leading: Icon(Icons.person_outline), title: Text('Sobre você')),
                ),
                PopupMenuItem(
                  value: 'profiles',
                  child: ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(state.profiles.length > 1 ? 'Trocar de perfil' : 'Perfil de empresa (PJ/MEI)'),
                  ),
                ),
                if (AppIcon.supported)
                  CheckedPopupMenuItem(
                    value: 'icon',
                    checked: state.dynamicIcon,
                    child: const Text('Ícone que muda com o mês'),
                  ),
                const PopupMenuItem(
                  value: 'categories',
                  child: ListTile(leading: Icon(Icons.category_outlined), title: Text('Categorias')),
                ),
                const PopupMenuItem(
                  value: 'achievements',
                  child: ListTile(leading: Icon(Icons.emoji_events_outlined), title: Text('Conquistas')),
                ),
                if (Reminders.supported)
                  const PopupMenuItem(
                    value: 'reminders',
                    child: ListTile(leading: Icon(Icons.notifications_outlined), title: Text('Lembretes')),
                  ),
                const PopupMenuItem(
                  value: 'import',
                  child: ListTile(leading: Icon(Icons.upload_file_outlined), title: Text('Importar extrato')),
                ),
                if (BankNotifications.supported)
                  const PopupMenuItem(
                    value: 'bank',
                    child: ListTile(leading: Icon(Icons.bolt_outlined), title: Text('Gastos do banco')),
                  ),
                const PopupMenuItem(
                  value: 'export',
                  child: ListTile(leading: Icon(Icons.table_view_outlined), title: Text('Exportar planilha')),
                ),
                const PopupMenuItem(
                  value: 'whatsapp',
                  child: ListTile(leading: Icon(Icons.chat_outlined), title: Text('Conectar WhatsApp')),
                ),
                const PopupMenuItem(
                  value: 'privacy',
                  child: ListTile(leading: Icon(Icons.shield_outlined), title: Text('Política de privacidade')),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(leading: Icon(Icons.logout), title: Text('Sair')),
                ),
                const PopupMenuItem(
                  value: 'logout_all',
                  child: ListTile(leading: Icon(Icons.devices_outlined), title: Text('Sair de todos os aparelhos')),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'reset',
                  child: ListTile(leading: Icon(Icons.restart_alt), title: Text('Começar do zero')),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_forever_outlined, color: Color(0xFFE5484D)),
                    title: Text('Excluir minha conta', style: TextStyle(color: Color(0xFFE5484D))),
                  ),
                ),
              ],
              child: CircleAvatar(
                radius: 20,
                backgroundColor: cs.primaryContainer,
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: [
        for (var i = 0; i < _pages.length; i++) _visited.contains(i) ? _pages[i] : const SizedBox.shrink(),
      ]),
      floatingActionButton: _index <= 1
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const TransactionFormScreen())),
              icon: const Icon(Icons.add),
              label: const Text('Lançar'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _visited.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Lançamentos'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'IA'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Planejar'),
        ],
      ),
    );
  }
}
