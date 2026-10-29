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

  test('Assinar o Plus manda a Idempotency-Key e lê o plano do servidor (RN-51)', () async {
    final keys = <String?>[];
    final api = ApiClient(client: MockClient((req) async {
      if (req.url.path.endsWith('/me/plan')) {
        return http.Response(jsonEncode({
          'plan': 'plus', 'source': 'trial', 'trialEndsAt': '2026-11-28T15:00:00Z',
          'paidUntil': null, 'subscriptionStatus': null, 'monthlyPrice': 4.0,
        }), 200);
      }
      keys.add(req.headers['Idempotency-Key']);
      return http.Response(jsonEncode({'subscriptionId': 's1', 'initPoint': 'https://mp.test/checkout'}), 200);
    }))
      ..token = 't';

    expect(await api.subscribe('intencao-1'), 'https://mp.test/checkout');
    await api.subscribe('intencao-1'); // tocou de novo: mesma chave, o servidor devolve a mesma assinatura
    expect(keys, ['intencao-1', 'intencao-1']);

    final plan = await api.plan();
    expect(plan.isPlus, isTrue);
    expect(plan.inTrial, isTrue);
    expect(plan.subscribed, isFalse);
    expect(plan.monthlyPrice, 4.0);
  });
}
