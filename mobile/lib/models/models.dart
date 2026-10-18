enum TxType { income, expense }

TxType _type(String v) => v == 'Income' ? TxType.income : TxType.expense;
String txTypeToJson(TxType t) => t == TxType.income ? 'Income' : 'Expense';
double _d(dynamic v) => (v as num).toDouble();

class Account {
  final String id, name, color, icon;

  /// [balance]: só lançamentos pagos até hoje. [forecastBalance]: tudo até o fim do mês consultado.
  final double initialBalance, balance, forecastBalance;
  Account.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        color = j['color'],
        icon = j['icon'] ?? 'account_balance_wallet',
        initialBalance = _d(j['initialBalance']),
        balance = _d(j['balance']),
        forecastBalance = _d(j['forecastBalance']);
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
        isPaid = j['isPaid'];
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
  final String id, categoryId, categoryName, categoryColor, month;
  final double limit, spent;
  double get progress => limit == 0 ? 0 : spent / limit;
  Budget.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        categoryId = j['categoryId'],
        categoryName = j['categoryName'],
        categoryColor = j['categoryColor'],
        month = j['month'],
        limit = _d(j['limit']),
        spent = _d(j['spent']);
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
  Insights.fromJson(Map<String, dynamic> j)
      : summary = j['summary'] ?? '',
        alerts = List<String>.from(j['alerts'] ?? []),
        tips = List<String>.from(j['tips'] ?? []),
        potentialSavings = _d(j['potentialSavings'] ?? 0),
        healthScore = (j['healthScore'] as num? ?? 0).toInt();
}
