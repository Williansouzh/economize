import 'dart:convert';

import 'package:financas_app/models/models.dart';
import 'package:financas_app/screens/analysis_screen.dart';
import 'package:financas_app/services/api_client.dart';
import 'package:financas_app/services/app_icon.dart';
import 'package:financas_app/utils/format.dart';
import 'package:financas_app/widgets/about_fields.dart';
import 'package:financas_app/widgets/count_up.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  test('o perfil de empresa vai no header X-Profile; o pessoal não manda header (RN-47)', () async {
    final headers = <String?>[];
    final api = ApiClient(client: MockClient((req) async {
      headers.add(req.headers['X-Profile']);
      return http.Response('[]', 200);
    }))
      ..token = 't';

    await api.accounts();
    api.profileId = 'empresa-1';
    await api.accounts();
    api.profileId = null;
    await api.accounts();

    expect(headers, [null, 'empresa-1', null]);
  });

  test('o chat devolve a resposta e quantas perguntas restam (RN-48)', () async {
    final api = ApiClient(client: MockClient((req) async => http.Response(jsonEncode({'answer': 'Oi!', 'remaining': 7}), 200)))
      ..token = 't';
    final (answer, remaining) = await api.ask('oi', '2026-10');
    expect(answer, 'Oi!');
    expect(remaining, 7);
  });

  test('cota acabou vira ApiException 429 com a mensagem da API', () async {
    final api = ApiClient(
        client: MockClient((req) async => http.Response(jsonEncode({'error': 'Suas 20 perguntas de hoje acabaram.'}), 429)))
      ..token = 't';
    await expectLater(
        api.ask('oi', '2026-10'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 429)));
  });

  test('ícone do app por situação do mês (RN-49)', () {
    expect(AppIcon.variantFor('otimo'), 'padrao');
    expect(AppIcon.variantFor('bom'), 'padrao');
    expect(AppIcon.variantFor('sem_dados'), 'padrao');
    expect(AppIcon.variantFor('atencao'), 'atencao');
    expect(AppIcon.variantFor('critico'), 'alerta');
  });

  test('questionário: ano de nascimento e renda', () {
    final d = AboutDraft();
    d.birthYear.text = '1999';
    d.income.text = '4.500,00';
    expect(d.validYear, isTrue);
    expect(d.age, DateTime.now().year - 1999);
    expect(d.monthlyIncome, 4500);
    d.birthYear.text = '${DateTime.now().year - 5}';
    expect(d.validYear, isFalse);
  });

  testWidgets('valor sobe até o número final', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CountUpMoney(1234.5)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(money(1234.5)), findsNothing); // ainda subindo
    await tester.pumpAndSettle();
    expect(find.text(money(1234.5)), findsOneWidget);
  });

  testWidgets('análise mostra a situação, a comparação com o IBGE e os pontos', (tester) async {
    final a = Analysis.fromJson({
      'kind': 'initial',
      'status': 'acima',
      'headline': 'Sua renda está acima da maioria',
      'message': 'Você ganha mais que cerca de 91% das pessoas de 25 a 29 anos.',
      'income': 6000,
      'benchmark': {
        'ageGroup': '25-29', 'ageGroupLabel': '25 a 29 anos', 'mean': 3104, 'median': 2200, 'region': 'NE',
        'regionName': 'Nordeste', 'regionMean': 2215, 'percentile': 91, 'source': 'IBGE, PNAD Contínua',
      },
      'points': [
        {'icon': 'flag', 'tone': 'info', 'text': 'Uma boa primeira meta: R\$ 18.000 de reserva.'},
      ],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [AnalysisView(a)]))));
    await tester.pumpAndSettle();
    expect(find.text('Sua renda está acima da maioria'), findsOneWidget);
    expect(find.text('ACIMA DA MÉDIA'), findsOneWidget);
    expect(find.text('91%'), findsOneWidget);
    expect(find.textContaining('No Nordeste'), findsOneWidget);
    expect(find.textContaining('R\$ 18.000 de reserva'), findsOneWidget);
  });

  testWidgets('teto do MEI no ritmo de estourar avisa quanto faturar por mês', (tester) async {
    final m = MeiSummary.fromJson({
      'year': 2026, 'monthsLeft': 3, 'revenue': 70000, 'limit': 81000, 'percent': 86.4,
      'projectedRevenue': 84000, 'monthlyRoom': 3666.67, 'status': 'atencao',
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MeiCard(m))));
    await tester.pumpAndSettle();
    expect(find.text('86%'), findsOneWidget);
    expect(find.textContaining(money(84000)), findsOneWidget);
    expect(find.textContaining('${money(3666.67)} por mês'), findsOneWidget);
  });
}
