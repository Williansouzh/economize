import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

class ApiClient {
  String? token;
  void Function()? onUnauthorized;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$apiBaseUrl/api$path').replace(queryParameters: query);

  Future<dynamic> _send(Future<http.Response> request) async {
    final http.Response res;
    try {
      res = await request.timeout(const Duration(seconds: 90));
    } catch (_) {
      throw ApiException('Não foi possível conectar ao servidor ($apiBaseUrl).');
    }
    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException('Sessão expirada ou credenciais inválidas.', 401);
    }
    final body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final msg = body is Map ? (body['error'] ?? body['detail'] ?? body['title']) : null;
      throw ApiException(msg?.toString() ?? 'Erro ${res.statusCode}', res.statusCode);
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, String>? q]) =>
      _send(http.get(_uri(path, q), headers: _headers));
  Future<dynamic> post(String path, Object body) =>
      _send(http.post(_uri(path), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> put(String path, Object body) =>
      _send(http.put(_uri(path), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> delete(String path) => _send(http.delete(_uri(path), headers: _headers));

  // ---- Auth ----
  Future<Map<String, dynamic>> login(String email, String password) async =>
      await post('/auth/login', {'email': email, 'password': password});
  Future<Map<String, dynamic>> register(String name, String email, String password) async =>
      await post('/auth/register', {'name': name, 'email': email, 'password': password});

  // ---- Dados ----
  Future<Dashboard> dashboard(String month) async =>
      Dashboard.fromJson(await get('/dashboard', {'month': month}));

  Future<List<Transaction>> transactions(String month) async =>
      (await get('/transactions', {'month': month}) as List)
          .map((e) => Transaction.fromJson(e))
          .toList();

  Future<List<Account>> accounts() async =>
      (await get('/accounts') as List).map((e) => Account.fromJson(e)).toList();

  Future<List<TxCategory>> categories() async =>
      (await get('/categories') as List).map((e) => TxCategory.fromJson(e)).toList();

  Future<void> saveTransaction({
    String? id,
    required String accountId,
    required String categoryId,
    required String description,
    required double amount,
    required TxType type,
    required DateTime date,
    required bool isPaid,
  }) async {
    final body = {
      'accountId': accountId,
      'categoryId': categoryId,
      'description': description,
      'amount': amount,
      'type': txTypeToJson(type),
      'date': date.toIso8601String().substring(0, 10),
      'isPaid': isPaid,
    };
    id == null ? await post('/transactions', body) : await put('/transactions/$id', body);
  }

  Future<void> deleteTransaction(String id) => delete('/transactions/$id');

  Future<void> createAccount(String name, double initialBalance) =>
      post('/accounts', {'name': name, 'initialBalance': initialBalance});

  Future<void> saveBudget(String categoryId, String month, double limit) =>
      post('/budgets', {'categoryId': categoryId, 'month': month, 'limit': limit});
  Future<void> deleteBudget(String id) => delete('/budgets/$id');

  // ---- WhatsApp ----
  Future<String?> linkedWhatsApp() async => (await get('/me'))['whatsAppPhone'];
  Future<String> whatsAppLinkCode() async => (await post('/me/whatsapp-code', {}))['code'];
  Future<void> unlinkWhatsApp() => delete('/me/whatsapp');

  // ---- IA (DeepSeek via backend) ----
  Future<Insights> insights(String month) async =>
      Insights.fromJson(await post('/insights', {'month': month}));
  Future<String> ask(String question, String month) async =>
      (await post('/insights/chat', {'question': question, 'month': month}))['answer'];
}
