import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String money(double v) => _currency.format(v);

final _amount = NumberFormat('#,##0.00', 'pt_BR');

/// Valor no formato dos campos de dinheiro: "1.234,56".
String amountText(double v) => _amount.format(v);

/// Campo de dinheiro no estilo dos apps de banco: só se digitam números e os dois últimos
/// viram os centavos ("1250" → "12,50"). Com [signed], um "-" em qualquer ponto deixa o valor negativo.
class MoneyInputFormatter extends TextInputFormatter {
  final bool signed;
  MoneyInputFormatter({this.signed = false});

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 13) digits = digits.substring(0, 13);
    final sign = signed && newValue.text.contains('-') ? '-' : '';
    final text = digits.isEmpty ? sign : '$sign${amountText(int.parse(digits) / 100)}';
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

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

/// Paleta de categorias (direção de arte, out/2026): mesma luminância e croma médio, tons espaçados
/// e longe do vermelho de despesa e do verde de receita. Cada cor tem a versão do tema escuro.
/// É também a paleta dos seletores de cor de conta e de meta.
const categoryPalette = <(String light, String dark, String name)>[
  ('#B55E43', '#ED987D', 'Terracota'),
  ('#A86B16', '#DFA360', 'Âmbar'),
  ('#728426', '#A8BC69', 'Oliva'),
  ('#008E96', '#46C6CD', 'Turquesa'),
  ('#3080BC', '#72B8F2', 'Azul'),
  ('#6673C1', '#9DABF7', 'Índigo'),
  ('#8B66B3', '#C19FE9', 'Lavanda'),
  ('#A85C90', '#E095C7', 'Ameixa'),
  ('#607089', '#A3B3CC', 'Ardósia'),
  ('#668E93', '#ACCBCE', 'Névoa'),
];
final categoryColors = [for (final c in categoryPalette) c.$1];

/// Cores antigas (Material saturadas) → a cor mais próxima da paleta nova. A API já migra o que está
/// salvo; isto cobre o que ainda chegar no formato antigo.
const _legacyColors = {
  '#E53935': '#B55E43', '#F44336': '#B55E43', '#F4511E': '#B55E43', '#FF5722': '#B55E43',
  '#FB8C00': '#A86B16', '#FF9800': '#A86B16', '#6D4C41': '#A86B16', '#795548': '#A86B16',
  '#F9A825': '#728426', '#CDDC39': '#728426', '#7CB342': '#728426', '#43A047': '#728426',
  '#4CAF50': '#728426', '#8BC34A': '#728426',
  '#00897B': '#008E96', '#009688': '#008E96', '#00ACC1': '#008E96', '#0C7A68': '#008E96',
  '#1E88E5': '#3080BC', '#2196F3': '#3080BC',
  '#3949AB': '#6673C1', '#3F51B5': '#6673C1', '#5E35B1': '#6673C1',
  '#8E24AA': '#8B66B3', '#9C27B0': '#8B66B3',
  '#D81B60': '#A85C90', '#E91E63': '#A85C90',
  '#546E7A': '#607089', '#607D8B': '#607089',
  '#9E9E9E': '#668E93',
};

/// Cor de uma categoria ou meta no tema atual: a versão clara (L 58%) ou a escura (L 76%) da paleta.
Color paletteColor(String hex, {bool dark = false}) {
  final h = hex.toUpperCase();
  final light = _legacyColors[h] ?? h;
  for (final c in categoryPalette) {
    if (c.$1 == light || c.$2 == light) return hexColor(dark ? c.$2 : c.$1);
  }
  // Cor fora da paleta (conta com a cor do banco, por exemplo): no escuro, clareia para não sumir.
  final color = hexColor(light);
  return dark ? Color.lerp(color, Colors.white, .35)! : color;
}

/// Atalho de [paletteColor] que lê o tema do [context].
Color tintOf(BuildContext context, String hex) =>
    paletteColor(hex, dark: Theme.of(context).brightness == Brightness.dark);

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

/// Cores para contas: a paleta das categorias (a cor do banco, se já estiver salva, continua valendo).
final accountColors = categoryColors;

/// Valor arredondado, sem centavos ("R\$ 4.465"): resumos e frases. Listas e saldos usam [money].
final _currencyShort = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 0);
String moneyShort(double v) => _currencyShort.format(v);

/// "R\$ 350/mês" sem quebrar a linha no meio (o intl já separa "R\$" do número com espaço não separável).
String perMonth(double v) => '${moneyShort(v)}/mês';

/// Plural simples do português: plural(2, 'conta', 'contas') → "2 contas".
String plural(int n, String one, String many) => Intl.plural(n, one: '$n $one', other: '$n $many');

String percent(double v) => '${(v * 100).toStringAsFixed(v.abs() < .1 ? 1 : 0).replaceAll('.', ',')}%';

/// Texto escuro ou claro, o que contrastar melhor com [background].
Color onColor(Color background) =>
    background.computeLuminance() > .55 ? Colors.black87 : Colors.white;
