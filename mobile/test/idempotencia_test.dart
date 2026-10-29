import 'dart:convert';

import 'package:financas_app/models/models.dart';
import 'package:financas_app/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Reenviar o mesmo lançamento manda a mesma Idempotency-Key; mudar o conteúdo, outra (RN-45)', () async {
    final keys = <String?>[];
    final api = ApiClient(client: MockClient((req) async {
      keys.add(req.headers['Idempotency-Key']);
      return http.Response(jsonEncode({'id': 'tx-1'}), 201);
    }))
      ..token = 't';

    Future<String?> save(double amount, {String? key = 'tela-1'}) => api.saveTransaction(
          accountId: 'a', categoryId: 'c', description: 'almoço', amount: amount,
          type: TxType.expense, date: DateTime(2026, 10, 10), isPaid: true, idempotencyKey: key);

    await save(30); // primeira tentativa (ex.: deu timeout)
    await save(30); // tocou em salvar de novo: o servidor devolve o mesmo lançamento
    await save(35); // mudou o valor: é outro lançamento
    await save(30, key: null);

    expect(keys[0], startsWith('tela-1-'));
    expect(keys[1], keys[0]);
    expect(keys[2], isNot(keys[0]));
    expect(keys[3], isNull);
    expect(keys.whereType<String>().every((k) => k.length <= 100), isTrue); // limite do servidor
  });
}
