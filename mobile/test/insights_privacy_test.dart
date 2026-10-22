import 'dart:convert';

import 'package:financas_app/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const insights = {'summary': 'ok', 'alerts': [], 'tips': [], 'potentialSavings': 0, 'healthScore': 50};

  test('Insights e chat levam a escolha de enviar ou não as descrições (RN-16)', () async {
    final bodies = <Map<String, dynamic>>[];
    final api = ApiClient(client: MockClient((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      final reply = req.url.path.endsWith('/chat') ? {'answer': 'oi'} : insights;
      return http.Response(jsonEncode(reply), 200);
    }))
      ..token = 't';

    await api.insights('2026-10', includeDescriptions: false);
    await api.ask('quanto gastei?', '2026-10', includeDescriptions: false);
    await api.insights('2026-10');

    expect(bodies[0]['includeDescriptions'], false);
    expect(bodies[1]['includeDescriptions'], false);
    expect(bodies[2]['includeDescriptions'], true); // padrão: envia, como antes
  });
}
