import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'budgets_screen.dart';
import 'categories_screen.dart';
import 'dashboard_screen.dart';
import 'delete_account_screen.dart';
import 'insights_screen.dart';
import 'transaction_form_screen.dart';
import 'transactions_screen.dart';
import 'whatsapp_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _titles = ['Visão geral', 'Lançamentos', 'Insights IA', 'Orçamentos'];
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
                'categories' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
                'privacy' => launchUrl(Uri.parse(privacyPolicyUrl), mode: LaunchMode.externalApplication),
                'delete' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text(name.isEmpty ? 'Minha conta' : name)),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'categories',
                  child: ListTile(leading: Icon(Icons.category_outlined), title: Text('Categorias')),
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
      body: IndexedStack(index: _index, children: _pages),
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
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Lançamentos'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'IA'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Orçamentos'),
        ],
      ),
    );
  }
}
