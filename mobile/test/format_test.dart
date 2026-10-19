import 'package:financas_app/screens/transaction_form_screen.dart';
import 'package:financas_app/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('valores digitados em reais viram número', () {
    expect(parseAmount('1.234,56'), 1234.56);
    expect(parseAmount('R\$ 10,5'), 10.5);
    expect(parseAmount('1234.56'), 1234.56);
    expect(parseAmount('abc'), isNull);
  });

  test('dinheiro e porcentagem no formato brasileiro', () {
    expect(money(1234.5).replaceAll(' ', ' '), 'R\$ 1.234,50');
    expect(percent(.5), '50%');
    expect(percent(.055), '5,5%');
  });

  test('mês por extenso', () {
    expect(monthLabel(DateTime(2026, 10)), 'Outubro 2026');
  });
}
