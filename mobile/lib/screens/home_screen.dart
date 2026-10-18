import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'budgets_screen.dart';
import 'dashboard_screen.dart';
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
                Text(firstName.isEmpty ? 'Minhas Finanças' : firstName),
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
                'whatsapp' => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const WhatsAppScreen())),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text(name.isEmpty ? 'Minha conta' : name)),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'whatsapp',
                  child: ListTile(leading: Icon(Icons.chat_outlined), title: Text('Conectar WhatsApp')),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: ListTile(leading: Icon(Icons.logout), title: Text('Sair')),
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
