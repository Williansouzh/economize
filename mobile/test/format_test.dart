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

  test('campo de dinheiro põe a vírgula sozinho', () {
    String type(String text, {bool signed = false}) => MoneyInputFormatter(signed: signed)
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text))
        .text;
    expect(type('5'), '0,05');
    expect(type('1250'), '12,50');
    expect(type('123456'), '1.234,56');
    expect(type('12,5'), '1,25'); // apagar o último dígito anda a vírgula
    expect(type(''), '');
    expect(type('-1000'), '10,00');
    expect(type('-1000', signed: true), '-10,00');
    expect(parseAmount(type('123456')), 1234.56);
    expect(amountText(50), '50,00');
  });

  test('dinheiro e porcentagem no formato brasileiro', () {
    expect(money(1234.5).replaceAll(' ', ' '), 'R\$ 1.234,50');
    expect(percent(.5), '50%');
    expect(percent(.055), '5,5%');
  });

  test('mês por extenso', () {
    expect(monthLabel(DateTime(2026, 10)), 'Outubro 2026');
  });

  test('cores antigas de categoria viram a cor mais próxima da paleta nova, com versão escura', () {
    expect(paletteColor('#F44336'), hexColor('#B55E43'));
    expect(paletteColor('#9e9e9e'), hexColor('#668E93'));
    expect(paletteColor('#B55E43', dark: true), hexColor('#ED987D'));
    expect(paletteColor('#ED987D'), hexColor('#B55E43'));
  });

  test('sugestão de categoria pela descrição', () {
    expect(suggestCategoryName('Uber pro trabalho'), 'Transporte');
    expect(suggestCategoryName('almoço com a equipe'), 'Alimentação');
    expect(suggestCategoryName('Netflix'), 'Assinaturas');
    expect(suggestCategoryName('presente da Ana'), 'Compras');
    expect(suggestCategoryName('qualquer coisa'), isNull);
    // "99" só como palavra: não pega "R\$ 199".
    expect(suggestCategoryName('compra 199'), isNull);
  });

  test('plural e valor por mês', () {
    expect(plural(1, 'conta', 'contas'), '1 conta');
    expect(plural(3, 'conta', 'contas'), '3 contas');
    expect(perMonth(350), '${moneyShort(350)}/mês');
  });
}
