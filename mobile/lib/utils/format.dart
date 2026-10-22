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
  'swap_horiz': Icons.swap_horiz,
};
IconData categoryIcon(String name) => _icons[name] ?? Icons.category;

const incomeColor = Color(0xFF2E7D32);
const expenseColor = Color(0xFFC62828);
const transferColor = Color(0xFF546E7A);
