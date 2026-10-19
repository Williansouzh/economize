import 'dart:convert';

import 'package:financas_app/services/api_client.dart';
import 'package:financas_app/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _dashboard = {
  'totalBalance': 100,
  'forecastBalance': 100,
  'income': 0,
  'expenses': 0,
  'monthResult': 0,
  'pendingIncome': 0,
  'pendingExpenses': 0,
  'accounts': [],
  'expensesByCategory': [],
  'budgets': [],
};

void main() {
  // Sem os lembretes do Android nos testes (eles usam canais de plataforma).
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  AppState stateWith(Future<http.Response> Function(http.Request) handler) =>
      AppState(api: ApiClient(client: MockClient(handler))..token = 't');

  test('Início e Orçamentos pedindo o dashboard juntos fazem uma requisição só', () async {
    var calls = 0;
    final state = stateWith((req) async {
      if (!req.url.path.endsWith('/dashboard')) return http.Response('[]', 200); // contas e categorias
      calls++;
      return http.Response(jsonEncode(_dashboard), 200);
    });
    final r = await Future.wait([state.dashboard(), state.dashboard()]);
    expect(r[0].totalBalance, 100);
    expect(calls, 1);

    // Algo mudou: busca de novo.
    state.dataChanged();
    await state.dashboard();
    expect(calls, 2);
  });

  test('erro não fica guardado: a próxima tentativa chama a API de novo', () async {
    var calls = 0;
    final state = stateWith((req) async {
      calls++;
      return calls == 1 ? http.Response('falhou', 500) : http.Response(jsonEncode(_dashboard), 200);
    });
    await expectLater(state.dashboard(), throwsA(isA<ApiException>()));
    expect((await state.dashboard()).totalBalance, 100);
    expect(calls, 2);
  });

  test('resposta de erro em texto puro vira mensagem amigável', () async {
    final state = stateWith((req) async => http.Response('<html>Bad Gateway</html>', 502));
    await expectLater(
      state.api.accounts(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('servidor teve um problema'))),
    );
  });

  test('o mês selecionado entra na chave do cache', () async {
    final months = <String?>[];
    final state = stateWith((req) async {
      months.add(req.url.queryParameters['month']);
      return http.Response(jsonEncode(_dashboard), 200);
    });
    await state.dashboard();
    state.changeMonth(-1);
    await state.dashboard();
    state.changeMonth(1);
    await state.dashboard(); // mês já visto: vem do cache
    expect(months.length, 2);
    expect(months[0], isNot(months[1]));
  });
}
