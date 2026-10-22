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
  /// Um cliente só para o app todo: reaproveita a conexão (e o TLS) entre as chamadas,
  /// em vez de abrir uma nova a cada requisição.
  final http.Client _http;
  String? token;

  ApiClient({http.Client? client}) : _http = client ?? http.Client();
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
    // Erros de servidor ou de proxy podem vir em texto puro ou HTML, não em JSON.
    Object? body;
    try {
      body = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      if (res.statusCode < 400) throw ApiException('Resposta inválida do servidor.', res.statusCode);
    }
    if (res.statusCode >= 400) {
      final msg = body is Map ? (body['error'] ?? body['detail'] ?? body['title']) : null;
      throw ApiException(
        msg?.toString() ??
            (res.statusCode >= 500
                ? 'O servidor teve um problema. Tente de novo em instantes.'
                : 'Erro ${res.statusCode}'),
        res.statusCode,
      );
    }
    return body;
  }

  Future<dynamic> get(String path, [Map<String, String>? q]) =>
      _send(_http.get(_uri(path, q), headers: _headers));
  Future<dynamic> post(String path, Object body) =>
      _send(_http.post(_uri(path), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> put(String path, Object body) =>
      _send(_http.put(_uri(path), headers: _headers, body: jsonEncode(body)));
  Future<dynamic> delete(String path) => _send(_http.delete(_uri(path), headers: _headers));

  // ---- Auth ----
  Future<Map<String, dynamic>> login(String email, String password) async =>
      await post('/auth/login', {'email': email, 'password': password});
  Future<Map<String, dynamic>> register(String name, String email, String password) async =>
      await post('/auth/register', {'name': name, 'email': email, 'password': password});

  /// Troca o token atual por um novo, com prazo renovado (RN-32).
  Future<Map<String, dynamic>> refreshToken() async => await post('/me/token', {});

  /// Encerra a sessão em todos os aparelhos, inclusive neste (RN-32).
  Future<void> logoutEverywhere() => delete('/me/sessions');

  /// "Esqueci minha senha": envia um código por e-mail (RN-38).
  Future<void> forgotPassword(String email) => post('/auth/forgot-password', {'email': email});
  Future<Map<String, dynamic>> resetPassword(String email, String code, String newPassword) async =>
      await post('/auth/reset-password', {'email': email, 'code': code, 'newPassword': newPassword});

  /// Erro não tratado no app: vai para o log do servidor. Nunca lança exceção.
  Future<void> reportError(String message, String? stack, String platform, String version) async {
    try {
      await _http
          .post(_uri('/client-errors'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'message': message, 'stack': stack, 'platform': platform, 'version': version}))
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

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

  /// Cria ou edita uma categoria e devolve como ficou salva.
  Future<TxCategory> saveCategory({
    String? id,
    required String name,
    required TxType type,
    required String icon,
    required String color,
  }) async {
    final body = {'name': name, 'type': txTypeToJson(type), 'icon': icon, 'color': color};
    return TxCategory.fromJson(id == null ? await post('/categories', body) : await put('/categories/$id', body));
  }

  Future<void> deleteCategory(String id) => delete('/categories/$id');

  /// Exclui uma conta ou cartão com os lançamentos e transferências dela.
  Future<void> deleteWalletAccount(String id) => delete('/accounts/$id');

  /// [repeat]: só na criação. 'monthly' repete o valor por [repeatCount] meses; 'installments'
  /// divide [amount] (total) em [repeatCount] parcelas. [future]: na edição, vale também para os próximos da série.
  Future<void> saveTransaction({
    String? id,
    required String accountId,
    required String categoryId,
    required String description,
    required double amount,
    required TxType type,
    required DateTime date,
    required bool isPaid,
    String? repeat,
    int repeatCount = 0,
    bool future = false,
  }) async {
    final body = {
      'accountId': accountId,
      'categoryId': categoryId,
      'description': description,
      'amount': amount,
      'type': txTypeToJson(type),
      'date': _day(date),
      'isPaid': isPaid,
      if (repeat != null) 'repeat': {'kind': repeat, 'count': repeatCount},
    };
    id == null
        ? await post('/transactions', body)
        : await put('/transactions/$id${future ? '?scope=future' : ''}', body);
  }

  Future<void> deleteTransaction(String id, {bool future = false}) =>
      delete('/transactions/$id${future ? '?scope=future' : ''}');

  /// Busca em todos os meses (até 100 resultados, os mais recentes primeiro).
  Future<List<Transaction>> searchTransactions({String? q, String? categoryId, String? accountId, TxType? type}) async =>
      (await get('/transactions/search', {
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        'categoryId': ?categoryId,
        'accountId': ?accountId,
        if (type != null) 'type': txTypeToJson(type),
      }) as List)
          .map((e) => Transaction.fromJson(e))
          .toList();

  /// Pendentes (a pagar e a receber) dos próximos [days] dias, para os lembretes.
  Future<List<Transaction>> upcoming({int days = 30}) async =>
      (await get('/transactions/upcoming', {'days': '$days'}) as List).map((e) => Transaction.fromJson(e)).toList();

  /// Fatura do cartão que fecha em [month] (yyyy-MM); sem mês, a que está aberta hoje.
  Future<Invoice> invoice(String accountId, {String? month}) async =>
      Invoice.fromJson(await get('/accounts/$accountId/invoice', {'month': ?month}));

  // ---- Metas, progresso e exportação ----
  Future<List<Goal>> goals() async => (await get('/goals') as List).map((e) => Goal.fromJson(e)).toList();
  Future<Goal> saveGoal({String? id, required String name, required double target, DateTime? deadline,
      required String icon, required String color}) async {
    final body = {
      'name': name,
      'target': target,
      'deadline': deadline == null ? null : _day(deadline),
      'icon': icon,
      'color': color,
    };
    return Goal.fromJson(id == null ? await post('/goals', body) : await put('/goals/$id', body));
  }

  Future<Goal> depositGoal(String id, double amount) async =>
      Goal.fromJson(await post('/goals/$id/deposit', {'amount': amount}));
  Future<void> deleteGoal(String id) => delete('/goals/$id');
  Future<Progress> progress() async => Progress.fromJson(await get('/me/progress'));

  /// CSV com todos os lançamentos e transferências (bytes, com BOM para o Excel).
  Future<List<int>> exportCsv() async {
    final http.Response res;
    try {
      res = await _http.get(_uri('/export/transactions.csv'), headers: _headers).timeout(const Duration(seconds: 90));
    } catch (_) {
      throw ApiException('Não foi possível conectar ao servidor ($apiBaseUrl).');
    }
    if (res.statusCode == 401) {
      onUnauthorized?.call();
      throw ApiException('Sessão expirada ou credenciais inválidas.', 401);
    }
    if (res.statusCode >= 400) throw ApiException('Não foi possível exportar (erro ${res.statusCode}).', res.statusCode);
    return res.bodyBytes;
  }

  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> saveAccount({
    String? id,
    required String name,
    required double initialBalance,
    required String color,
    required String icon,
    bool isCard = false,
    double? creditLimit,
    int? closingDay,
    int? dueDay,
  }) async {
    final body = {
      'name': name,
      'initialBalance': initialBalance,
      'color': color,
      'icon': icon,
      'kind': isCard ? 'CreditCard' : 'Regular',
      if (isCard) ...{'creditLimit': creditLimit, 'closingDay': closingDay, 'dueDay': dueDay},
    };
    id == null ? await post('/accounts', body) : await put('/accounts/$id', body);
  }

  Future<void> saveBudget(String categoryId, String month, double limit, {bool recurring = false}) =>
      post('/budgets', {'categoryId': categoryId, 'month': month, 'limit': limit, 'recurring': recurring});

  /// No mês de origem exclui o orçamento; num mês herdado, para de repetir a partir de [month].
  Future<void> deleteBudget(String id, String month) =>
      _send(_http.delete(_uri('/budgets/$id', {'month': month}), headers: _headers));

  Future<List<Transfer>> transfers(String month) async =>
      (await get('/transfers', {'month': month}) as List).map((e) => Transfer.fromJson(e)).toList();

  Future<void> saveTransfer({
    String? id,
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required DateTime date,
    required String description,
    required bool isPaid,
  }) async {
    final body = {
      'fromAccountId': fromAccountId,
      'toAccountId': toAccountId,
      'amount': amount,
      'date': _day(date),
      'description': description,
      'isPaid': isPaid,
    };
    id == null ? await post('/transfers', body) : await put('/transfers/$id', body);
  }

  Future<void> deleteTransfer(String id) => delete('/transfers/$id');

  // ---- Importação (RN-42) e gastos detectados (RN-43) ----
  Future<List<ImportLine>> importParse(String fileName, List<int> bytes) async {
    final r = await post('/import/parse', {'fileName': fileName, 'content': base64Encode(bytes)});
    return [for (final j in r['items']) ImportLine.fromJson(j)];
  }

  Future<List<ImportItem>> importPreview(String accountId, List<ImportLine> lines) async {
    final r = await post('/import/preview', {
      'accountId': accountId,
      'items': [
        for (final l in lines)
          {'date': _day(l.date), 'description': l.description, 'amount': l.amount, 'externalId': l.externalId}
      ],
    }) as List;
    return [for (final j in r) ImportItem.fromJson(j)];
  }

  Future<int> importCommit(String accountId, List<ImportItem> items) async {
    final r = await post('/import/commit', {
      'accountId': accountId,
      'items': [
        for (final i in items)
          {
            'date': _day(i.date),
            'description': i.description,
            'amount': i.amount,
            'type': txTypeToJson(i.type),
            'categoryId': i.categoryId,
            'externalId': i.externalId,
          }
      ],
    });
    return r['created'];
  }

  // ---- Conta ----
  /// Exclui a conta e todos os dados. Pede a senha de novo (RN-30).
  Future<void> deleteAccount(String password) => _send(
      _http.delete(_uri('/me'), headers: _headers, body: jsonEncode({'password': password})));

  /// Apaga os dados financeiros e mantém o cadastro (RN-41). Também pede a senha.
  Future<void> resetData(String password) => _send(
      _http.post(_uri('/me/reset'), headers: _headers, body: jsonEncode({'password': password})));

  // ---- WhatsApp ----
  Future<String?> linkedWhatsApp() async => (await get('/me'))['whatsAppPhone'];

  /// Só o super admin enxerga o painel (RN-44); para os outros a API responde false.
  Future<bool> isAdmin() async => (await get('/me'))['isAdmin'] == true;
  Future<AdminStats> adminStats() async => AdminStats.fromJson(await get('/admin/stats'));
  Future<String> whatsAppLinkCode() async => (await post('/me/whatsapp-code', {}))['code'];
  Future<void> unlinkWhatsApp() => delete('/me/whatsapp');

  // ---- IA (DeepSeek via backend) ----
  /// [includeDescriptions] = false: o DeepSeek recebe só data, categoria e valor das despesas.
  Future<Insights> insights(String month, {bool includeDescriptions = true}) async => Insights.fromJson(
      await post('/insights', {'month': month, 'includeDescriptions': includeDescriptions}));
  Future<String> ask(String question, String month, {bool includeDescriptions = true}) async =>
      (await post('/insights/chat',
          {'question': question, 'month': month, 'includeDescriptions': includeDescriptions}))['answer'];
}
