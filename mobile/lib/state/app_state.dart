import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/bank_notifications.dart';
import '../services/reminders.dart';

/// Estado global: sessão do usuário, mês selecionado e dados de apoio (contas/categorias).
class AppState extends ChangeNotifier {
  final ApiClient api;
  final reminders = Reminders();
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

  /// Compras e Pix lidos das notificações do banco, esperando revisão (RN-43, só Android).
  final bankNotifications = BankNotifications();
  List<DetectedNotification> detected = [];

  Future<void> refreshDetected() async {
    if (!BankNotifications.supported || !loggedIn) return;
    try {
      detected = await bankNotifications.pending();
      notifyListeners();
    } catch (e) {
      debugPrint('Notificações do banco: $e');
    }
  }

  /// Conta usada da última vez para os gastos de cada app de banco.
  Future<String?> bankAccount(String package) async {
    final id = await _storage.read(key: 'bank_account_$package');
    return accounts.any((a) => a.id == id) ? id : null;
  }

  Future<void> rememberBankAccount(String package, String id) => _storage.write(key: 'bank_account_$package', value: id);

  /// Incrementado sempre que algo muda, para as telas recarregarem.
  int revision = 0;

  /// Respostas por mês, compartilhadas entre as abas (Início e Orçamentos usam o mesmo
  /// dashboard) e reaproveitadas ao voltar para um mês já visto. Limpo quando algo muda.
  final _cache = <String, Future<Object>>{};

  Future<T> _cached<T extends Object>(String key, Future<T> Function() load) {
    final hit = _cache[key];
    if (hit != null) return hit.then((v) => v as T);
    final f = load();
    _cache[key] = f;
    // Erro não fica guardado: a próxima tentativa chama a API de novo.
    f.then<void>((_) {}, onError: (Object _) {
      if (identical(_cache[key], f)) _cache.remove(key);
    });
    return f;
  }

  Future<Dashboard> dashboard() {
    final m = monthKey;
    return _cached('dashboard:$m', () => api.dashboard(m));
  }

  Future<(List<Transaction>, List<Transfer>)> monthEntries() {
    final m = monthKey;
    return _cached('entries:$m', () async {
      final r = await Future.wait([api.transactions(m), api.transfers(m)]);
      return (r[0] as List<Transaction>, r[1] as List<Transfer>);
    });
  }

  Future<List<Goal>> goals() => _cached('goals', api.goals);
  Future<Progress> progress() => _cached('progress', api.progress);

  /// Puxar para atualizar: descarta o que estava guardado.
  void clearCache() => _cache.clear();

  // Última categoria usada por tipo: o próximo lançamento já começa com ela.
  final _lastCategory = <TxType, String>{};
  String? lastCategory(TxType type) => _lastCategory[type];
  void rememberCategory(TxType type, String id) {
    _lastCategory[type] = id;
    _storage.write(key: 'last_category_${type.name}', value: id);
  }

  // Última conta usada: sem ela, o padrão é a primeira conta que não é cartão.
  String? _lastAccount;
  String? get defaultAccountId {
    if (accounts.any((a) => a.id == _lastAccount)) return _lastAccount;
    return (accounts.where((a) => !a.isCard).firstOrNull ?? accounts.firstOrNull)?.id;
  }

  void rememberAccount(String id) {
    _lastAccount = id;
    _storage.write(key: 'last_account', value: id);
  }

  AppState({ApiClient? api}) : api = api ?? ApiClient() {
    this.api.onUnauthorized = logout;
  }

  Future<void> init() async {
    api.token = await _storage.read(key: 'token');
    userName = await _storage.read(key: 'name');
    onboardingSeen = await _storage.read(key: 'onboarding_seen') == '1';
    needsSetup = loggedIn && await _storage.read(key: 'setup_pending') == '1';
    for (final t in TxType.values) {
      final id = await _storage.read(key: 'last_category_${t.name}');
      if (id != null) _lastCategory[t] = id;
    }
    _lastAccount = await _storage.read(key: 'last_account');
    initialized = true;
    notifyListeners();
    if (loggedIn) {
      // Começa a buscar o Início enquanto a abertura ainda está na tela.
      dashboard().ignore();
      loadReferenceData();
      _refreshToken();
      reminders.syncSoon(api);
      bankNotifications.setActive(true).ignore();
      refreshDetected();
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
  Future<void> resetPassword(String email, String code, String newPassword) =>
      _auth(api.resetPassword(email, code, newPassword));
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
    _cache.clear();
    reminders.syncSoon(api);
    bankNotifications.setActive(true).ignore();
    await loadReferenceData();
    notifyListeners();
  }

  Future<void> logout() async {
    api.token = null;
    userName = null;
    _cache.clear();
    reminders.cancelAll();
    // Para de guardar notificações do banco e apaga a fila: nada de mostrar gastos de outra pessoa.
    bankNotifications.setActive(false).ignore();
    detected = [];
    needsSetup = false;
    // Só os dados da sessão: "já viu a apresentação" continua valendo neste aparelho.
    _lastCategory.clear();
    _lastAccount = null;
    for (final key in ['token', 'name', 'setup_pending', 'last_category_income', 'last_category_expense', 'last_account']) {
      await _storage.delete(key: key);
    }
    notifyListeners();
  }

  /// "Começar do zero": a conta continua, os dados somem e o app volta para a configuração inicial.
  Future<void> resetData(String password) async {
    await api.resetData(password);
    _lastCategory.clear();
    _lastAccount = null;
    for (final key in ['last_category_income', 'last_category_expense', 'last_account']) {
      await _storage.delete(key: key);
    }
    needsSetup = true;
    await _storage.write(key: 'setup_pending', value: '1');
    dataChanged();
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
    _cache.clear();
    reminders.syncSoon(api);
    revision++;
    loadReferenceData();
    notifyListeners();
  }
}
