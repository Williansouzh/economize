using Financas.Api.Models;

namespace Financas.Api.Dtos;

public record RegisterRequest(string Name, string Email, string Password);
public record LoginRequest(string Email, string Password);
public record AuthResponse(string Token, string Name, string Email);

public record AccountRequest(string Name, decimal InitialBalance, string? Color, string? Icon,
    AccountKind Kind = AccountKind.Regular, decimal? CreditLimit = null, int? ClosingDay = null, int? DueDay = null);
/// <param name="Balance">Saldo atual: lançamentos pagos com data até hoje.</param>
/// <param name="ForecastBalance">Saldo previsto: todos os lançamentos até o fim do mês consultado.</param>
/// <param name="OpenInvoice">Só cartão: total da fatura aberta hoje (RN-35).</param>
public record AccountDto(Guid Id, string Name, decimal InitialBalance, decimal Balance, decimal ForecastBalance,
    string Color, string Icon, AccountKind Kind = AccountKind.Regular, decimal? CreditLimit = null,
    int? ClosingDay = null, int? DueDay = null, decimal? OpenInvoice = null);

/// <param name="Month">Mês (yyyy-MM) em que a fatura fecha.</param>
/// <param name="Paid">Pagamentos (transferências para o cartão) feitos entre o fechamento desta fatura e o da próxima.</param>
public record InvoiceDto(Guid AccountId, string AccountName, string Month, DateOnly PeriodStart, DateOnly ClosingDate,
    DateOnly DueDate, decimal Total, decimal Paid, bool IsOpen, IReadOnlyList<TransactionDto> Items);

public record CategoryRequest(string Name, TransactionType Type, string? Icon, string? Color);
public record CategoryDto(Guid Id, string Name, TransactionType Type, string Icon, string Color);

/// <param name="Repeat">Só na criação: repete todo mês ou divide em parcelas (RN-33).</param>
public record TransactionRequest(
    Guid AccountId, Guid CategoryId, string Description, decimal Amount,
    TransactionType Type, DateOnly Date, bool IsPaid = true, RepeatRequest? Repeat = null);

/// <param name="Kind">"monthly": o mesmo valor por <paramref name="Count"/> meses.
/// "installments": <c>Amount</c> é o total, dividido em <paramref name="Count"/> parcelas mensais.</param>
public record RepeatRequest(string Kind, int Count);

public record TransactionDto(
    Guid Id, Guid AccountId, string AccountName, Guid CategoryId, string CategoryName,
    string CategoryIcon, string CategoryColor, string Description, decimal Amount,
    TransactionType Type, DateOnly Date, bool IsPaid,
    Guid? SeriesId = null, int? InstallmentNumber = null, int? InstallmentCount = null);

public record BudgetRequest(Guid CategoryId, string Month, decimal Limit, bool Recurring = false);
/// <param name="Month">Mês em que o orçamento foi definido (pode ser anterior ao consultado).</param>
/// <param name="Inherited">Veio da repetição de um mês anterior (RN-27).</param>
public record BudgetDto(Guid Id, Guid CategoryId, string CategoryName, string CategoryColor,
    string Month, decimal Limit, decimal Spent, bool Recurring, bool Inherited);

public record TransferRequest(Guid FromAccountId, Guid ToAccountId, decimal Amount, DateOnly Date,
    string? Description, bool IsPaid = true);
public record TransferDto(Guid Id, Guid FromAccountId, string FromAccountName, Guid ToAccountId,
    string ToAccountName, decimal Amount, DateOnly Date, string Description, bool IsPaid);

public record CategoryTotal(Guid CategoryId, string Name, string Color, decimal Total, double Percent);

public record DashboardDto(
    string Month, decimal TotalBalance, decimal ForecastBalance,
    decimal Income, decimal Expenses, decimal MonthResult,
    decimal PendingIncome, decimal PendingExpenses,
    IReadOnlyList<AccountDto> Accounts, IReadOnlyList<CategoryTotal> ExpensesByCategory,
    IReadOnlyList<BudgetDto> Budgets);

/// <param name="IncludeDescriptions">false: o DeepSeek recebe só data, categoria e valor das despesas, sem as descrições.</param>
public record InsightsRequest(string? Month, bool IncludeDescriptions = true);
/// <param name="Cached">Veio da última análise guardada, porque os dados do mês não mudaram (RN-48).</param>
public record InsightsDto(string Summary, List<string> Alerts, List<string> Tips,
    decimal PotentialSavings, int HealthScore, bool Cached = false);

public record ChatRequest(string Question, string? Month, bool IncludeDescriptions = true);
/// <param name="Remaining">Perguntas que ainda restam hoje (RN-48).</param>
public record ChatResponse(string Answer, int? Remaining = null);
public record AiQuotaDto(int ChatUsed, int ChatLimit, int ChatRemaining, DateTime ResetsAt);

// ---------- Questionário (RN-46), perfis PF/PJ (RN-47) e análises ----------
/// <param name="Sources">clt, servidor, autonomo, mei, estagio, aposentadoria, beneficio, pensao, aluguel, investimentos, outros.</param>
/// <param name="MainGoal">organizar, dividas, reserva, investir, sonho, aposentadoria.</param>
public record AboutRequest(int? BirthYear, string? State, List<string>? Sources, int? JobCount, decimal? MonthlyIncome, string? MainGoal);
public record AboutDto(int? BirthYear, int? Age, string? State, List<string> Sources, int? JobCount,
    decimal? MonthlyIncome, string? MainGoal, bool Completed);

public record ProfileRequest(string Name, string? Cnpj, bool IsMei = true);
public record ProfileDto(Guid Id, string Name, ProfileKind Kind, string? Cnpj, bool IsMei);

/// <param name="Status">"ok", "atencao" (no ritmo de passar do teto) ou "estourou".</param>
public record MeiSummaryDto(int Year, decimal Revenue, decimal Limit, double Percent, decimal ProjectedRevenue,
    decimal MonthlyRoom, int MonthsLeft, string Status);

/// <param name="Percentile">Porcentagem aproximada das pessoas da faixa que ganham menos que o usuário.</param>
public record BenchmarkDto(string AgeGroup, string AgeGroupLabel, int Mean, int Median, string Region, string RegionName,
    int RegionMean, int? Percentile, string Source);

/// <param name="Tone">good, warn, bad ou info.</param>
public record AnalysisPointDto(string Icon, string Tone, string Text);

/// <param name="Kind">"initial" (pelo questionário) ou "monthly" (pelos lançamentos do mês).</param>
/// <param name="Status">Inicial: acima, na_media, abaixo ou sem_dados. Mensal: otimo, bom, atencao, critico ou sem_dados.</param>
public record AnalysisDto(string Kind, string? Month, string Status, string Headline, string Message,
    decimal? Income, decimal? Expenses, double? SavingsRate, BenchmarkDto? Benchmark, MeiSummaryDto? Mei,
    List<AnalysisPointDto> Points);

public record GoalRequest(string Name, decimal Target, DateOnly? Deadline, string? Icon, string? Color);
public record GoalDepositRequest(decimal Amount);
public record GoalDto(Guid Id, string Name, decimal Target, decimal Saved, DateOnly? Deadline, string Icon, string Color,
    double Progress, decimal? MonthlyNeeded);

/// <param name="Current">Progresso até desbloquear ("3 de 7 dias"); nulo nas conquistas de sim ou não.</param>
public record AchievementDto(string Id, string Title, string Description, string Icon, bool Unlocked,
    int? Current = null, int? Target = null);
/// <param name="Streak">Dias seguidos, até hoje ou ontem, com pelo menos um lançamento registrado (RN-37).</param>
public record ProgressDto(int Streak, int BestStreak, bool RegisteredToday, IReadOnlyList<AchievementDto> Achievements);

public record ForgotPasswordRequest(string Email);
public record ResetPasswordRequest(string Email, string Code, string NewPassword);
public record ClientErrorRequest(string Message, string? Stack, string? Platform, string? Version);

public record MeDto(string Name, string Email, string? WhatsAppPhone, bool IsAdmin = false);

// ---------- Super admin (RN-44) ----------
/// <summary>Cadastros e usuários ativos (que abriram o app ou usaram o WhatsApp) em um dia.</summary>
public record AdminDayDto(DateOnly Day, int Signups, int Active);
public record AdminUserDto(string Name, string Email, DateTime CreatedAt, DateTime? LastSeenAt, int Transactions, bool WhatsApp);
public record AdminStatsDto(int TotalUsers, int NewToday, int New7Days, int New30Days,
    int ActiveToday, int Active7Days, int Active30Days, int WhatsAppLinked, int Transactions30Days,
    List<AdminDayDto> Days, List<AdminUserDto> RecentUsers);
public record DeleteAccountRequest(string Password);
public record LinkCodeDto(string Code, DateTime ExpiresAt);
public record AgentLinkRequest(string Phone, string Code);
public record AgentTokenRequest(string Phone);

// ---------- Importação (RN-42) e gastos detectados nas notificações (RN-43) ----------
/// <summary>Arquivo do extrato em base64 (OFX, CSV ou PDF, até 5 MB).</summary>
public record ImportParseRequest(string FileName, string Content);
/// <summary>Linha lida do arquivo ou da notificação. Amount com sinal: negativo é saída.</summary>
public record ImportLine(DateOnly Date, string Description, decimal Amount, string? ExternalId);
public record ImportPreviewRequest(Guid AccountId, List<ImportLine> Items);
/// <summary>Status: "new", "imported" (já veio antes, mesmo identificador) ou "duplicate" (parece um
/// lançamento que já existe). TransferLike: pagamento de fatura, aplicação etc., que costumam ser transferências.</summary>
public record ImportPreviewItem(DateOnly Date, string Description, decimal Amount, TransactionType Type, Guid? CategoryId,
    string? ExternalId, string Status, bool TransferLike);
public record ImportCommitItem(DateOnly Date, string? Description, decimal Amount, TransactionType Type, Guid CategoryId, string? ExternalId);
public record ImportCommitRequest(Guid AccountId, List<ImportCommitItem> Items);
