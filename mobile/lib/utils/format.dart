import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String money(double v) => _currency.format(v);

String monthLabel(DateTime m) {
  final s = DateFormat('MMMM yyyy', 'pt_BR').format(m);
  return s[0].toUpperCase() + s.substring(1);
}

Color hexColor(String hex) => Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));

const _icons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'home': Icons.home,
  'directions_car': Icons.directions_car,
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'celebration': Icons.celebration,
  'shopping_bag': Icons.shopping_bag,
  'subscriptions': Icons.subscriptions,
  'more_horiz': Icons.more_horiz,
  'payments': Icons.payments,
  'work': Icons.work,
  'trending_up': Icons.trending_up,
  'attach_money': Icons.attach_money,
};
IconData categoryIcon(String name) => _icons[name] ?? Icons.category;

/// Ícones que o usuário pode escolher para uma conta (nome salvo no backend → ícone).
const accountIcons = <String, IconData>{
  'account_balance_wallet': Icons.account_balance_wallet,
  'account_balance': Icons.account_balance,
  'credit_card': Icons.credit_card,
  'savings': Icons.savings,
  'payments': Icons.payments,
  'trending_up': Icons.trending_up,
  'currency_exchange': Icons.currency_exchange,
  'store': Icons.store,
  'work': Icons.work,
  'home': Icons.home,
  'flight': Icons.flight,
  'pix': Icons.pix,
};
IconData accountIcon(String name) => accountIcons[name] ?? Icons.account_balance_wallet;

/// Cores sugeridas para contas (as dos bancos mais comuns aparecem primeiro).
const accountColors = [
  '#00A86B', '#8A05BE', '#EC7000', '#CC092F', '#FFCC00', '#0070AF',
  '#1E88E5', '#00897B', '#5E35B1', '#F4511E', '#6D4C41', '#546E7A',
];

const incomeColor = Color(0xFF1B9E5A);
const expenseColor = Color(0xFFE5484D);
const warningColor = Color(0xFFF5A524);

String percent(double v) => '${(v * 100).toStringAsFixed(v.abs() < .1 ? 1 : 0).replaceAll('.', ',')}%';

/// Texto escuro ou claro, o que contrastar melhor com [background].
Color onColor(Color background) =>
    background.computeLuminance() > .55 ? Colors.black87 : Colors.white;
