import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String money(double v) => _currency.format(v);

String monthLabel(DateTime m) {
  final s = DateFormat('MMMM yyyy', 'pt_BR').format(m);
  return s[0].toUpperCase() + s.substring(1);
}

Color hexColor(String hex) => Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));

/// Ícones de categoria (nome salvo no backend → ícone). Os 13 primeiros são os das categorias
/// padrão; os demais aparecem no seletor ao criar ou editar uma categoria.
const categoryIcons = <String, IconData>{
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
  'local_grocery_store': Icons.local_grocery_store,
  'fastfood': Icons.fastfood,
  'local_cafe': Icons.local_cafe,
  'local_bar': Icons.local_bar,
  'local_gas_station': Icons.local_gas_station,
  'directions_bus': Icons.directions_bus,
  'flight': Icons.flight,
  'bolt': Icons.bolt,
  'water_drop': Icons.water_drop,
  'wifi': Icons.wifi,
  'smartphone': Icons.smartphone,
  'fitness_center': Icons.fitness_center,
  'spa': Icons.spa,
  'medication': Icons.medication,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'checkroom': Icons.checkroom,
  'sports_esports': Icons.sports_esports,
  'movie': Icons.movie,
  'music_note': Icons.music_note,
  'menu_book': Icons.menu_book,
  'card_giftcard': Icons.card_giftcard,
  'volunteer_activism': Icons.volunteer_activism,
  'build': Icons.build,
  'cleaning_services': Icons.cleaning_services,
  'receipt_long': Icons.receipt_long,
  'credit_card': Icons.credit_card,
  'account_balance': Icons.account_balance,
  'savings': Icons.savings,
  'sell': Icons.sell,
  'storefront': Icons.storefront,
  'redeem': Icons.redeem,
  'category': Icons.category,
};
IconData categoryIcon(String name) => categoryIcons[name] ?? Icons.category;

/// Cores sugeridas para categorias.
const categoryColors = [
  '#E53935', '#F4511E', '#FB8C00', '#F9A825', '#7CB342', '#43A047',
  '#00897B', '#00ACC1', '#1E88E5', '#3949AB', '#8E24AA', '#D81B60',
  '#6D4C41', '#546E7A', '#9E9E9E',
];

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
