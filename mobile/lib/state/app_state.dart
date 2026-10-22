import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import '../services/api_client.dart';

/// Estado global: sessão do usuário, mês selecionado e dados de apoio (contas/categorias).
class AppState extends ChangeNotifier {
  final api = ApiClient();
  final _storage = const FlutterSecureStorage();

  bool initialized = false;
  String? userName;
  bool get loggedIn => api.token != null;

  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String get monthKey => '${month.year}-${month.month.toString().padLeft(2, '0')}';

  List<Account> accounts = [];
  List<TxCategory> categories = [];

  /// Se as descrições dos lançamentos podem ir para o DeepSeek nos insights. Salvo no aparelho.
  bool sendDescriptionsToAi = true;

  Future<void> setSendDescriptionsToAi(bool value) async {
    sendDescriptionsToAi = value;
    await _storage.write(key: 'ai_descriptions', value: value.toString());
    notifyListeners();
  }

  /// Incrementado sempre que algo muda, para as telas recarregarem.
  int revision = 0;

  AppState() {
    api.onUnauthorized = logout;
  }

  Future<void> init() async {
    api.token = await _storage.read(key: 'token');
    userName = await _storage.read(key: 'name');
    sendDescriptionsToAi = await _storage.read(key: 'ai_descriptions') != 'false';
    initialized = true;
    notifyListeners();
    if (loggedIn) loadReferenceData();
  }

  Future<void> login(String email, String password) => _auth(api.login(email, password));
  Future<void> register(String name, String email, String password) =>
      _auth(api.register(name, email, password));

  Future<void> _auth(Future<Map<String, dynamic>> call) async {
    final res = await call;
    api.token = res['token'];
    userName = res['name'];
    await _storage.write(key: 'token', value: api.token);
    await _storage.write(key: 'name', value: userName);
    await loadReferenceData();
    notifyListeners();
  }

  Future<void> logout() async {
    api.token = null;
    userName = null;
    // Só a sessão: preferências como a de privacidade da IA continuam no aparelho.
    await _storage.delete(key: 'token');
    await _storage.delete(key: 'name');
    notifyListeners();
  }

  Future<void> loadReferenceData() async {
    try {
      final r = await Future.wait([api.accounts(), api.categories()]);
      accounts = r[0] as List<Account>;
      categories = r[1] as List<TxCategory>;
      notifyListeners();
    } on ApiException {
      // As telas mostram o erro quando tentarem carregar seus próprios dados.
    }
  }

  void changeMonth(int delta) {
    month = DateTime(month.year, month.month + delta);
    notifyListeners();
  }

  void dataChanged() {
    revision++;
    loadReferenceData();
    notifyListeners();
  }
}
