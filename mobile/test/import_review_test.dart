import 'dart:convert';

import 'package:financas_app/models/models.dart';
import 'package:financas_app/screens/import_screen.dart';
import 'package:financas_app/services/api_client.dart';
import 'package:financas_app/state/app_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('revisão: o que já existe vem desmarcado e só o marcado é importado', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(412, 915) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    Map<String, dynamic>? committed;
    Map<String, dynamic> item(String desc, double amount, String status, {bool transfer = false}) => {
          'date': '2026-10-05', 'description': desc, 'amount': amount, 'type': 'Expense', 'categoryId': 'c1',
          'externalId': 'h:$desc', 'status': status, 'transferLike': transfer,
        };
    final api = ApiClient(client: MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/import/preview')) {
        return http.Response(jsonEncode([
          item('PADARIA REAL', 42.9, 'new'),
          item('MERCADO', 120, 'duplicate'),
          item('Pagamento de fatura', 500, 'new', transfer: true),
        ]), 200);
      }
      if (path.endsWith('/import/commit')) {
        committed = jsonDecode(req.body);
        return http.Response(jsonEncode({'created': 1}), 200);
      }
      return http.Response('[]', 200);
    }))
      ..token = 't';
    final state = AppState(api: api)
      ..accounts = [
        Account.fromJson({'id': 'a1', 'name': 'Nubank', 'color': '#8A05BE', 'initialBalance': 0, 'balance': 0, 'forecastBalance': 0, 'kind': 'Regular'}),
      ]
      ..categories = [TxCategory.fromJson({'id': 'c1', 'name': 'Alimentação', 'icon': 'restaurant', 'color': '#F44336', 'type': 'Expense'})];

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ImportReviewScreen(
                    title: 'extrato.csv',
                    lines: [ImportLine(DateTime(2026, 10, 5), 'x', -1, 'h:x')],
                    accountId: 'a1',
                    allowInvert: true,
                  ))),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Parece já lançado'), findsOneWidget);
    expect(find.text('Parece transferência ou pagamento de fatura'), findsOneWidget);
    expect(find.text('Importar 1 lançamento'), findsOneWidget);
    expect(tester.takeException(), isNull); // sem estouro de layout na largura de celular

    await tester.tap(find.text('Importar 1 lançamento'));
    await tester.pumpAndSettle();
    final items = committed!['items'] as List;
    expect(items.single['description'], 'PADARIA REAL');
    expect(committed!['accountId'], 'a1');
    expect(find.text('1 lançamento importado.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
