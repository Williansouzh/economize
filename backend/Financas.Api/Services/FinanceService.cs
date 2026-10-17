using System.Globalization;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Services;

/// <summary>Cálculos de saldo, totais por categoria e orçamentos.</summary>
public class FinanceService(AppDbContext db, AppClock clock)
{
    public DateOnly Today => clock.Today;

    /// <summary>Converte "AAAA-MM" no intervalo do mês. Vazio ou inválido = mês atual.</summary>
    public (DateOnly Start, DateOnly End, string Key) ParseMonth(string? month)
    {
        var date = DateOnly.TryParseExact(month + "-01", "yyyy-MM-dd", CultureInfo.InvariantCulture,
            DateTimeStyles.None, out var d) ? d : clock.Today;
        var start = new DateOnly(date.Year, date.Month, 1);
        return (start, start.AddMonths(1).AddDays(-1), start.ToString("yyyy-MM"));
    }

    public Task<List<Transaction>> GetTransactionsAsync(Guid userId, DateOnly start, DateOnly end) =>
        db.Transactions.AsNoTracking()
            .Include(t => t.Account).Include(t => t.Category)
            .Where(t => t.UserId == userId && t.Date >= start && t.Date <= end)
            .OrderByDescending(t => t.Date)
            .ToListAsync();

    /// <summary>
    /// Saldo atual: só o que já aconteceu (pago e com data até hoje).
    /// Saldo previsto: tudo até <paramref name="forecastUntil"/>, inclusive pendentes e agendados.
    /// </summary>
    public async Task<List<AccountDto>> GetAccountsAsync(Guid userId, DateOnly? forecastUntil = null)
    {
        var today = clock.Today;
        var until = forecastUntil ?? ParseMonth(null).End;
        var lastDate = today > until ? today : until;
        var accounts = await db.Accounts.AsNoTracking().Where(a => a.UserId == userId).ToListAsync();
        // Agregação em memória: o provider SQLite não soma decimal no banco.
        var txs = await db.Transactions.AsNoTracking()
            .Where(t => t.UserId == userId && t.Date <= lastDate)
            .Select(t => new { t.AccountId, t.Amount, t.Type, t.IsPaid, t.Date })
            .ToListAsync();

        static decimal Signed(TransactionType type, decimal amount) =>
            type == TransactionType.Income ? amount : -amount;

        return accounts.Select(a =>
        {
            var mine = txs.Where(t => t.AccountId == a.Id).ToList();
            var current = mine.Where(t => t.IsPaid && t.Date <= today).Sum(t => Signed(t.Type, t.Amount));
            var forecast = mine.Where(t => t.Date <= until).Sum(t => Signed(t.Type, t.Amount));
            return new AccountDto(a.Id, a.Name, a.InitialBalance,
                a.InitialBalance + current, a.InitialBalance + forecast, a.Color);
        }).OrderBy(a => a.Name).ToList();
    }

    public static List<CategoryTotal> ExpensesByCategory(IEnumerable<Transaction> txs)
    {
        var expenses = txs.Where(t => t.Type == TransactionType.Expense).ToList();
        var total = expenses.Sum(t => t.Amount);
        return expenses
            .GroupBy(t => t.CategoryId)
            .Select(g => new CategoryTotal(
                g.Key, g.First().Category!.Name, g.First().Category!.Color, g.Sum(t => t.Amount),
                total == 0 ? 0 : Math.Round((double)(g.Sum(t => t.Amount) / total) * 100, 1)))
            .OrderByDescending(c => c.Total)
            .ToList();
    }

    public async Task<List<BudgetDto>> GetBudgetsAsync(Guid userId, string monthKey, IEnumerable<Transaction> monthTxs)
    {
        var budgets = await db.Budgets.AsNoTracking().Include(b => b.Category)
            .Where(b => b.UserId == userId && b.Month == monthKey).ToListAsync();
        return budgets.Select(b => new BudgetDto(
            b.Id, b.CategoryId, b.Category!.Name, b.Category.Color, b.Month, b.Limit,
            monthTxs.Where(t => t.CategoryId == b.CategoryId && t.Type == TransactionType.Expense)
                .Sum(t => t.Amount))).ToList();
    }

    public async Task<DashboardDto> GetDashboardAsync(Guid userId, string? month)
    {
        var (start, end, key) = ParseMonth(month);
        var txs = await GetTransactionsAsync(userId, start, end);
        var accounts = await GetAccountsAsync(userId, end);
        decimal Sum(TransactionType type, bool? paid = null) => txs
            .Where(t => t.Type == type && (paid is null || t.IsPaid == paid)).Sum(t => t.Amount);
        var income = Sum(TransactionType.Income);
        var expenses = Sum(TransactionType.Expense);

        return new DashboardDto(key, accounts.Sum(a => a.Balance), accounts.Sum(a => a.ForecastBalance),
            income, expenses, income - expenses,
            Sum(TransactionType.Income, paid: false), Sum(TransactionType.Expense, paid: false),
            accounts, ExpensesByCategory(txs), await GetBudgetsAsync(userId, key, txs));
    }
}
