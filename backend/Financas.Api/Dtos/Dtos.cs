using Financas.Api.Models;

namespace Financas.Api.Dtos;

public record RegisterRequest(string Name, string Email, string Password);
public record LoginRequest(string Email, string Password);
public record AuthResponse(string Token, string Name, string Email);

public record AccountRequest(string Name, decimal InitialBalance, string? Color);
/// <param name="Balance">Saldo atual: lançamentos pagos com data até hoje.</param>
/// <param name="ForecastBalance">Saldo previsto: todos os lançamentos até o fim do mês consultado.</param>
public record AccountDto(Guid Id, string Name, decimal InitialBalance, decimal Balance, decimal ForecastBalance, string Color);

public record CategoryRequest(string Name, TransactionType Type, string? Icon, string? Color);
public record CategoryDto(Guid Id, string Name, TransactionType Type, string Icon, string Color);

public record TransactionRequest(
    Guid AccountId, Guid CategoryId, string Description, decimal Amount,
    TransactionType Type, DateOnly Date, bool IsPaid = true);

public record TransactionDto(
    Guid Id, Guid AccountId, string AccountName, Guid CategoryId, string CategoryName,
    string CategoryIcon, string CategoryColor, string Description, decimal Amount,
    TransactionType Type, DateOnly Date, bool IsPaid);

public record BudgetRequest(Guid CategoryId, string Month, decimal Limit);
public record BudgetDto(Guid Id, Guid CategoryId, string CategoryName, string CategoryColor,
    string Month, decimal Limit, decimal Spent);

public record CategoryTotal(Guid CategoryId, string Name, string Color, decimal Total, double Percent);

public record DashboardDto(
    string Month, decimal TotalBalance, decimal ForecastBalance,
    decimal Income, decimal Expenses, decimal MonthResult,
    decimal PendingIncome, decimal PendingExpenses,
    IReadOnlyList<AccountDto> Accounts, IReadOnlyList<CategoryTotal> ExpensesByCategory,
    IReadOnlyList<BudgetDto> Budgets);

public record InsightsRequest(string? Month);
public record InsightsDto(string Summary, List<string> Alerts, List<string> Tips,
    decimal PotentialSavings, int HealthScore);

public record ChatRequest(string Question, string? Month);
public record ChatResponse(string Answer);

public record MeDto(string Name, string Email, string? WhatsAppPhone);
public record LinkCodeDto(string Code, DateTime ExpiresAt);
public record AgentLinkRequest(string Phone, string Code);
public record AgentTokenRequest(string Phone);
