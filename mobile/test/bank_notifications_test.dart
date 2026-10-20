import 'package:financas_app/services/bank_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 10, 20, 13, 45);
  (double, String)? parse(String title, String text) {
    final l = parseBankNotification(title, text, at, 'n:1');
    return l == null ? null : (l.amount, l.description);
  }

  test('compras no cartão: valor negativo e o estabelecimento como descrição', () {
    expect(parse('Compra aprovada', 'Compra de R\$ 42,90 APROVADA em PADARIA REAL para o cartão com final 1234.'),
        (-42.90, 'PADARIA REAL'));
    expect(parse('Itaú', 'Compra aprovada no cartão final 1234 de R\$ 1.250,00 em MAGAZINE LUIZA às 13:40'),
        (-1250.00, 'MAGAZINE LUIZA'));
    expect(parse('Inter', 'Você fez uma compra de R\$ 18,50 no débito em UBER *TRIP'), (-18.50, 'UBER *TRIP'));
  });

  test('Pix enviado e recebido', () {
    expect(parse('Pix enviado', 'Você enviou R\$ 50,00 para MARIA DA SILVA.'), (-50.00, 'MARIA DA SILVA'));
    expect(parse('Pix recebido', 'Você recebeu um Pix de R\$ 200,00 de JOÃO SOUZA'), (200.00, 'JOÃO SOUZA'));
    expect(parse('Transferência recebida', 'Você recebeu uma transferência de R\$ 3.500,00'), (3500.00, 'Transferência recebida'));
  });

  test('o que não é movimentação fica de fora', () {
    expect(parse('Sua fatura fechou', 'A fatura de outubro fechou em R\$ 1.234,56. Vence dia 10.'), isNull);
    expect(parse('Compra recusada', 'Compra de R\$ 99,90 em LOJA X foi recusada por falta de limite.'), isNull);
    expect(parse('Código', 'Seu código de segurança é 123456'), isNull);
    expect(parse('Oferta', 'Empréstimo de até R\$ 5.000,00 disponível para você'), isNull);
    expect(parse('Rendimento', 'Seu dinheiro rendeu R\$ 3,20 hoje'), isNull);
  });

  test('usa o dia da notificação e um identificador estável', () {
    final l = parseBankNotification('Compra aprovada', 'Compra de R\$ 10,00 em CAFE', at, 'n:abc')!;
    expect(l.date, DateTime(2026, 10, 20));
    expect(l.externalId, 'n:abc');
  });
}
