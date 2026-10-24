enum TxType { income, expense }

TxType _type(String v) => v == 'Income' ? TxType.income : TxType.expense;
String txTypeToJson(TxType t) => t == TxType.income ? 'Income' : 'Expense';
double _d(dynamic v) => (v as num).toDouble();

double? _dn(dynamic v) => v == null ? null : _d(v);
DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v);

class Account {
  final String id, name, color, icon;

  /// [balance]: só lançamentos pagos até hoje. [forecastBalance]: tudo até o fim do mês consultado.
  final double initialBalance, balance, forecastBalance;

  /// Cartão de crédito: limite, dias de fechamento e vencimento e total da fatura aberta hoje.
  final bool isCard;
  final double? creditLimit, openInvoice;
  final int? closingDay, dueDay;
  Account.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        color = j['color'],
        icon = j['icon'] ?? 'account_balance_wallet',
        initialBalance = _d(j['initialBalance']),
        balance = _d(j['balance']),
        forecastBalance = _d(j['forecastBalance']),
        isCard = j['kind'] == 'CreditCard',
        creditLimit = _dn(j['creditLimit']),
        openInvoice = _dn(j['openInvoice']),
        closingDay = j['closingDay'],
        dueDay = j['dueDay'];
}

class TxCategory {
  final String id, name, icon, color;
  final TxType type;
  TxCategory.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        icon = j['icon'],
        color = j['color'],
        type = _type(j['type']);
}

class Transaction {
  final String id, accountId, accountName, categoryId, categoryName;
  final String categoryIcon, categoryColor, description;
  final double amount;
  final TxType type;
  final DateTime date;
  final bool isPaid;

  /// Fixos e parcelados: [seriesId] liga os lançamentos criados juntos; parcela [installmentNumber]/[installmentCount].
  final String? seriesId;
  final int? installmentNumber, installmentCount;
  bool get inSeries => seriesId != null;
  Transaction.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        accountId = j['accountId'],
        accountName = j['accountName'],
        categoryId = j['categoryId'],
        categoryName = j['categoryName'],
        categoryIcon = j['categoryIcon'],
        categoryColor = j['categoryColor'],
        description = j['description'],
        amount = _d(j['amount']),
        type = _type(j['type']),
        date = DateTime.parse(j['date']),
        isPaid = j['isPaid'],
        seriesId = j['seriesId'],
        installmentNumber = j['installmentNumber'],
        installmentCount = j['installmentCount'];
}

class CategoryTotal {
  final String categoryId, name, color;
  final double total, percent;
  CategoryTotal.fromJson(Map<String, dynamic> j)
      : categoryId = j['categoryId'],
        name = j['name'],
        color = j['color'],
        total = _d(j['total']),
        percent = _d(j['percent']);
}

class Budget {
  final String id, categoryId, categoryName, categoryColor;

  /// Mês em que o orçamento foi definido; num mês herdado, é um mês anterior.
  final String month;
  final double limit, spent;

  /// [recurring]: repete nos meses seguintes. [inherited]: veio da repetição de um mês anterior.
  final bool recurring, inherited;
  double get progress => limit == 0 ? 0 : spent / limit;
  Budget.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        categoryId = j['categoryId'],
        categoryName = j['categoryName'],
        categoryColor = j['categoryColor'],
        month = j['month'],
        limit = _d(j['limit']),
        spent = _d(j['spent']),
        recurring = j['recurring'] ?? false,
        inherited = j['inherited'] ?? false;
}

/// Dinheiro movido entre duas contas: muda os saldos, mas não é receita nem despesa.
class Transfer {
  final String id, fromAccountId, fromAccountName, toAccountId, toAccountName, description;
  final double amount;
  final DateTime date;
  final bool isPaid;
  Transfer.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        fromAccountId = j['fromAccountId'],
        fromAccountName = j['fromAccountName'],
        toAccountId = j['toAccountId'],
        toAccountName = j['toAccountName'],
        description = j['description'],
        amount = _d(j['amount']),
        date = DateTime.parse(j['date']),
        isPaid = j['isPaid'];
}

class Dashboard {
  final double totalBalance, forecastBalance, income, expenses, monthResult;
  final double pendingIncome, pendingExpenses;
  final List<Account> accounts;
  final List<CategoryTotal> expensesByCategory;
  final List<Budget> budgets;
  Dashboard.fromJson(Map<String, dynamic> j)
      : totalBalance = _d(j['totalBalance']),
        forecastBalance = _d(j['forecastBalance']),
        income = _d(j['income']),
        expenses = _d(j['expenses']),
        monthResult = _d(j['monthResult']),
        pendingIncome = _d(j['pendingIncome']),
        pendingExpenses = _d(j['pendingExpenses']),
        accounts = (j['accounts'] as List).map((e) => Account.fromJson(e)).toList(),
        expensesByCategory =
            (j['expensesByCategory'] as List).map((e) => CategoryTotal.fromJson(e)).toList(),
        budgets = (j['budgets'] as List).map((e) => Budget.fromJson(e)).toList();
}

class Insights {
  final String summary;
  final List<String> alerts, tips;
  final double potentialSavings;
  final int healthScore;

  /// Veio da análise guardada: os dados do mês não mudaram desde a última vez (RN-48).
  final bool cached;
  Insights.fromJson(Map<String, dynamic> j)
      : summary = j['summary'] ?? '',
        alerts = List<String>.from(j['alerts'] ?? []),
        tips = List<String>.from(j['tips'] ?? []),
        potentialSavings = _d(j['potentialSavings'] ?? 0),
        healthScore = (j['healthScore'] as num? ?? 0).toInt(),
        cached = j['cached'] == true;
}

/// Perfil pessoal ou de empresa (PJ/MEI), com dados separados (RN-47).
class Profile {
  final String id, name;
  final bool isBusiness, isMei;
  final String? cnpj;
  const Profile({required this.id, required this.name, this.isBusiness = false, this.isMei = false, this.cnpj});
  Profile.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        isBusiness = j['kind'] == 'Business',
        isMei = j['isMei'] == true,
        cnpj = j['cnpj'];
}

/// Respostas do questionário do onboarding (RN-46).
class About {
  final int? birthYear, age, jobCount;
  final String? state, mainGoal;
  final List<String> sources;
  final double? monthlyIncome;
  final bool completed;
  About.fromJson(Map<String, dynamic> j)
      : birthYear = j['birthYear'],
        age = j['age'],
        jobCount = j['jobCount'],
        state = j['state'],
        mainGoal = j['mainGoal'],
        sources = List<String>.from(j['sources'] ?? []),
        monthlyIncome = _dn(j['monthlyIncome']),
        completed = j['completed'] == true;
}

class Benchmark {
  final String ageGroupLabel, regionName, source;
  final int mean, median, regionMean;
  final int? percentile;
  final bool hasRegion;
  Benchmark.fromJson(Map<String, dynamic> j)
      : ageGroupLabel = j['ageGroupLabel'],
        regionName = j['regionName'],
        source = j['source'],
        mean = j['mean'],
        median = j['median'],
        regionMean = j['regionMean'],
        percentile = j['percentile'],
        hasRegion = j['region'] != 'BR';
}

/// Faturamento do ano do MEI e o teto (RN-47).
class MeiSummary {
  final int year, monthsLeft;
  final double revenue, limit, percent, projectedRevenue, monthlyRoom;

  /// ok, atencao (no ritmo de passar do teto) ou estourou.
  final String status;
  MeiSummary.fromJson(Map<String, dynamic> j)
      : year = j['year'],
        monthsLeft = j['monthsLeft'],
        revenue = _d(j['revenue']),
        limit = _d(j['limit']),
        percent = _d(j['percent']),
        projectedRevenue = _d(j['projectedRevenue']),
        monthlyRoom = _d(j['monthlyRoom']),
        status = j['status'];
}

class AnalysisPoint {
  final String icon, tone, text;
  AnalysisPoint.fromJson(Map<String, dynamic> j)
      : icon = j['icon'],
        tone = j['tone'],
        text = j['text'];
}

/// Análise inicial (questionário) ou do mês (lançamentos), calculada pela API sem IA (RN-46).
class Analysis {
  final String kind, status, headline, message;
  final double? income, expenses, savingsRate;
  final Benchmark? benchmark;
  final MeiSummary? mei;
  final List<AnalysisPoint> points;
  Analysis.fromJson(Map<String, dynamic> j)
      : kind = j['kind'],
        status = j['status'],
        headline = j['headline'],
        message = j['message'],
        income = _dn(j['income']),
        expenses = _dn(j['expenses']),
        savingsRate = _dn(j['savingsRate']),
        benchmark = j['benchmark'] == null ? null : Benchmark.fromJson(j['benchmark']),
        mei = j['mei'] == null ? null : MeiSummary.fromJson(j['mei']),
        points = [for (final p in j['points'] ?? []) AnalysisPoint.fromJson(p)];
}

/// Fatura do cartão que fecha em [month] (compras de [periodStart] até a véspera de [closingDate]).
class Invoice {
  final String accountId, accountName, month;
  final DateTime periodStart, closingDate, dueDate;
  final double total, paid;
  final bool isOpen;
  final List<Transaction> items;
  double get remaining => (total - paid).clamp(0, double.infinity);
  Invoice.fromJson(Map<String, dynamic> j)
      : accountId = j['accountId'],
        accountName = j['accountName'],
        month = j['month'],
        periodStart = DateTime.parse(j['periodStart']),
        closingDate = DateTime.parse(j['closingDate']),
        dueDate = DateTime.parse(j['dueDate']),
        total = _d(j['total']),
        paid = _d(j['paid']),
        isOpen = j['isOpen'],
        items = (j['items'] as List).map((e) => Transaction.fromJson(e)).toList();
}

/// Meta de economia. [monthlyNeeded]: quanto guardar por mês para chegar no prazo.
class Goal {
  final String id, name, icon, color;
  final double target, saved, progress;
  final double? monthlyNeeded;
  final DateTime? deadline;
  bool get reached => saved >= target;
  Goal.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        icon = j['icon'],
        color = j['color'],
        target = _d(j['target']),
        saved = _d(j['saved']),
        progress = _d(j['progress']),
        monthlyNeeded = _dn(j['monthlyNeeded']),
        deadline = _date(j['deadline']);
}

class Achievement {
  final String id, title, description, icon;
  final bool unlocked;
  Achievement.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        title = j['title'],
        description = j['description'],
        icon = j['icon'],
        unlocked = j['unlocked'];
}

/// Sequência de dias registrando e conquistas.
class Progress {
  final int streak, bestStreak;
  final bool registeredToday;
  final List<Achievement> achievements;
  Progress.fromJson(Map<String, dynamic> j)
      : streak = j['streak'],
        bestStreak = j['bestStreak'],
        registeredToday = j['registeredToday'],
        achievements = (j['achievements'] as List).map((e) => Achievement.fromJson(e)).toList();
}

/// Linha de um extrato importado ou de um gasto detectado na notificação do banco (RN-42/43).
/// [amount] com sinal: negativo é saída.
class ImportLine {
  final DateTime date;
  final String description;
  final double amount;
  final String? externalId;
  const ImportLine(this.date, this.description, this.amount, this.externalId);
  ImportLine.fromJson(Map<String, dynamic> j)
      : date = DateTime.parse(j['date']),
        description = j['description'],
        amount = _d(j['amount']),
        externalId = j['externalId'];
}

/// Linha revisada antes de importar. [status]: "new", "imported" (já veio antes) ou "duplicate"
/// (parece um lançamento que já existe). [transferLike]: pagamento de fatura, aplicação etc.
class ImportItem {
  final DateTime date;
  final String description, status;
  final double amount;
  final String? externalId;
  final bool transferLike;
  TxType type;
  String? categoryId;
  bool selected;
  ImportItem.fromJson(Map<String, dynamic> j)
      : date = DateTime.parse(j['date']),
        description = j['description'],
        amount = _d(j['amount']),
        type = _type(j['type']),
        categoryId = j['categoryId'],
        externalId = j['externalId'],
        status = j['status'],
        transferLike = j['transferLike'],
        selected = j['status'] == 'new' && j['transferLike'] != true;
}

/// Painel do super admin (RN-44).
class AdminStats {
  final int totalUsers, newToday, new7Days, new30Days, activeToday, active7Days, active30Days;
  final int whatsAppLinked, transactions30Days;
  final List<AdminDay> days;
  final List<AdminUser> recentUsers;

  AdminStats.fromJson(Map<String, dynamic> j)
      : totalUsers = j['totalUsers'],
        newToday = j['newToday'],
        new7Days = j['new7Days'],
        new30Days = j['new30Days'],
        activeToday = j['activeToday'],
        active7Days = j['active7Days'],
        active30Days = j['active30Days'],
        whatsAppLinked = j['whatsAppLinked'],
        transactions30Days = j['transactions30Days'],
        days = [for (final d in j['days']) AdminDay.fromJson(d)],
        recentUsers = [for (final u in j['recentUsers']) AdminUser.fromJson(u)];
}

class AdminDay {
  final DateTime day;
  final int signups, active;
  AdminDay.fromJson(Map<String, dynamic> j)
      : day = DateTime.parse(j['day']),
        signups = j['signups'],
        active = j['active'];
}

class AdminUser {
  final String name, email;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final int transactions;
  final bool whatsApp;
  AdminUser.fromJson(Map<String, dynamic> j)
      : name = j['name'],
        email = j['email'],
        createdAt = DateTime.parse(j['createdAt']).toLocal(),
        lastSeenAt = j['lastSeenAt'] == null ? null : DateTime.parse(j['lastSeenAt']).toLocal(),
        transactions = j['transactions'],
        whatsApp = j['whatsApp'];
}
