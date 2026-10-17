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

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'logout' => state.logout(),
              'whatsapp' => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const WhatsAppScreen())),
              _ => null,
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text('Olá, ${state.userName ?? ''}')),
              const PopupMenuItem(value: 'whatsapp', child: Text('Conectar WhatsApp')),
              const PopupMenuItem(value: 'logout', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index <= 1
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const TransactionFormScreen())),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Lançamentos'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'IA'),
          NavigationDestination(icon: Icon(Icons.savings_outlined), selectedIcon: Icon(Icons.savings), label: 'Orçamentos'),
        ],
      ),
    );
  }
}
