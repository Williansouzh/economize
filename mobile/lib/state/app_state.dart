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

  /// Já viu a apresentação do app (fica no aparelho, vale para qualquer conta).
  bool onboardingSeen = false;

  /// Acabou de criar a conta e ainda não passou pela configuração guiada.
  bool needsSetup = false;

  /// A tela de login abre no modo "criar conta" (vindo do "Começar" da apresentação).
  bool preferRegister = false;

  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String get monthKey => '${month.year}-${month.month.toString().padLeft(2, '0')}';

  List<Account> accounts = [];
  List<TxCategory> categories = [];

  /// Incrementado sempre que algo muda, para as telas recarregarem.
  int revision = 0;

  AppState() {
    api.onUnauthorized = logout;
  }

  Future<void> init() async {
    api.token = await _storage.read(key: 'token');
    userName = await _storage.read(key: 'name');
    onboardingSeen = await _storage.read(key: 'onboarding_seen') == '1';
    needsSetup = loggedIn && await _storage.read(key: 'setup_pending') == '1';
    initialized = true;
    notifyListeners();
    if (loggedIn) {
      loadReferenceData();
      _refreshToken();
    }
  }

  /// O token vale poucos dias; renovar a cada abertura mantém conectado quem usa o app.
  /// Se a sessão foi encerrada em outro aparelho, a API responde 401 e o [logout] acontece sozinho.
  Future<void> _refreshToken() async {
    try {
      final res = await api.refreshToken();
      api.token = res['token'];
      await _storage.write(key: 'token', value: api.token);
    } on ApiException {
      // Sem internet: segue com o token atual.
    }
  }

  Future<void> login(String email, String password) => _auth(api.login(email, password));
  Future<void> register(String name, String email, String password) async {
    await _auth(api.register(name, email, password));
    needsSetup = true;
    await _storage.write(key: 'setup_pending', value: '1');
    notifyListeners();
  }

  Future<void> completeOnboarding({bool signIn = false}) async {
    onboardingSeen = true;
    preferRegister = !signIn;
    await _storage.write(key: 'onboarding_seen', value: '1');
    notifyListeners();
  }

  Future<void> completeSetup() async {
    needsSetup = false;
    await _storage.delete(key: 'setup_pending');
    notifyListeners();
  }

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
    needsSetup = false;
    // Só os dados da sessão: "já viu a apresentação" continua valendo neste aparelho.
    for (final key in ['token', 'name', 'setup_pending']) {
      await _storage.delete(key: key);
    }
    notifyListeners();
  }

  Future<void> logoutEverywhere() async {
    await api.logoutEverywhere();
    await logout();
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
