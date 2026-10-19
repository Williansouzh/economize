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
        var accounts = await db.Accounts.AsNoTracking().Where(a => a.UserId == userId).ToListAsync();

        // Somas feitas pelo PostgreSQL: uma linha por conta, sem trazer os lançamentos para a memória.
        var sums = await db.Transactions.AsNoTracking()
            .Where(t => t.UserId == userId && (t.Date <= today || t.Date <= until))
            .GroupBy(t => t.AccountId)
            .Select(g => new
            {
                AccountId = g.Key,
                Current = g.Sum(t => t.IsPaid && t.Date <= today
                    ? (t.Type == TransactionType.Income ? t.Amount : -t.Amount) : 0m),
                Forecast = g.Sum(t => t.Date <= until
                    ? (t.Type == TransactionType.Income ? t.Amount : -t.Amount) : 0m),
            })
            .ToDictionaryAsync(x => x.AccountId);

        // Transferências (RN-28): saem da conta de origem e entram na de destino, com as mesmas
        // regras de pago e de data dos lançamentos.
        var transfers = db.Transfers.AsNoTracking()
            .Where(t => t.UserId == userId && (t.Date <= today || t.Date <= until));
        var sent = await transfers.GroupBy(t => t.FromAccountId)
            .Select(g => new
            {
                AccountId = g.Key,
                Current = g.Sum(t => t.IsPaid && t.Date <= today ? t.Amount : 0m),
                Forecast = g.Sum(t => t.Date <= until ? t.Amount : 0m),
            })
            .ToDictionaryAsync(x => x.AccountId);
        var received = await transfers.GroupBy(t => t.ToAccountId)
            .Select(g => new
            {
                AccountId = g.Key,
                Current = g.Sum(t => t.IsPaid && t.Date <= today ? t.Amount : 0m),
                Forecast = g.Sum(t => t.Date <= until ? t.Amount : 0m),
            })
            .ToDictionaryAsync(x => x.AccountId);

        // Cartões: total da fatura aberta hoje (RN-35).
        var openInvoices = new Dictionary<Guid, decimal>();
        foreach (var card in accounts.Where(IsCard))
        {
            var (start, closing, _) = InvoicePeriod(OpenInvoiceMonth(today, card.ClosingDay!.Value), card.ClosingDay!.Value, card.DueDay!.Value);
            openInvoices[card.Id] = await InvoiceTotalAsync(userId, card.Id, start, closing);
        }

        return accounts.Select(a =>
        {
            var s = sums.GetValueOrDefault(a.Id);
            var o = sent.GetValueOrDefault(a.Id);
            var i = received.GetValueOrDefault(a.Id);
            var current = (s?.Current ?? 0) - (o?.Current ?? 0) + (i?.Current ?? 0);
            var forecast = (s?.Forecast ?? 0) - (o?.Forecast ?? 0) + (i?.Forecast ?? 0);
            return new AccountDto(a.Id, a.Name, a.InitialBalance,
                a.InitialBalance + current, a.InitialBalance + forecast, a.Color, a.Icon,
                a.Kind, a.CreditLimit, a.ClosingDay, a.DueDay,
                openInvoices.TryGetValue(a.Id, out var inv) ? inv : null);
        }).OrderBy(a => a.Name).ToList();
    }

    // ---------- Cartão de crédito (RN-35) ----------

    public static bool IsCard(Account a) => a.Kind == AccountKind.CreditCard && a.ClosingDay is not null && a.DueDay is not null;

    /// <summary>Dia <paramref name="day"/> do mês, limitado ao último dia (fechamento no dia 31 em fevereiro cai no 28/29).</summary>
    public static DateOnly DayOfMonth(DateOnly monthStart, int day) =>
        new(monthStart.Year, monthStart.Month, Math.Min(day, DateTime.DaysInMonth(monthStart.Year, monthStart.Month)));

    /// <summary>
    /// Fatura que fecha no mês <paramref name="monthStart"/>: compras de <c>Start</c> (fechamento anterior,
    /// inclusive) até a véspera de <c>Closing</c>. Compra feita no dia do fechamento já vai para a próxima.
    /// O vencimento cai no mesmo mês se o dia dele for depois do fechamento; senão, no mês seguinte.
    /// </summary>
    public static (DateOnly Start, DateOnly Closing, DateOnly Due) InvoicePeriod(DateOnly monthStart, int closingDay, int dueDay)
    {
        var start = DayOfMonth(monthStart.AddMonths(-1), closingDay);
        var closing = DayOfMonth(monthStart, closingDay);
        var due = DayOfMonth(dueDay > closingDay ? monthStart : monthStart.AddMonths(1), dueDay);
        return (start, closing, due);
    }

    /// <summary>Mês (primeiro dia) da fatura em que entra uma compra feita em <paramref name="date"/>.</summary>
    public static DateOnly OpenInvoiceMonth(DateOnly date, int closingDay)
    {
        var month = new DateOnly(date.Year, date.Month, 1);
        return date < DayOfMonth(month, closingDay) ? month : month.AddMonths(1);
    }

    private async Task<decimal> InvoiceTotalAsync(Guid userId, Guid accountId, DateOnly start, DateOnly closing) =>
        await db.Transactions.AsNoTracking()
            .Where(t => t.UserId == userId && t.AccountId == accountId && t.Date >= start && t.Date < closing)
            .SumAsync(t => t.Type == TransactionType.Expense ? t.Amount : -t.Amount);

    /// <summary>Fatura do cartão que fecha em <paramref name="month"/> (padrão: a aberta hoje).</summary>
    public async Task<InvoiceDto?> GetInvoiceAsync(Guid userId, Guid accountId, string? month)
    {
        var card = await db.Accounts.AsNoTracking().FirstOrDefaultAsync(a => a.Id == accountId && a.UserId == userId);
        if (card is null || !IsCard(card)) return null;
        var monthStart = month is null ? OpenInvoiceMonth(clock.Today, card.ClosingDay!.Value) : ParseMonth(month).Start;
        var (start, closing, due) = InvoicePeriod(monthStart, card.ClosingDay!.Value, card.DueDay!.Value);
        var nextClosing = DayOfMonth(monthStart.AddMonths(1), card.ClosingDay!.Value);

        var items = await db.Transactions.AsNoTracking().Include(t => t.Account).Include(t => t.Category)
            .Where(t => t.UserId == userId && t.AccountId == accountId && t.Date >= start && t.Date < closing)
            .OrderByDescending(t => t.Date).ToListAsync();
        var paid = await db.Transfers.AsNoTracking()
            .Where(t => t.UserId == userId && t.ToAccountId == accountId && t.Date >= closing && t.Date < nextClosing)
            .SumAsync(t => t.Amount);
        var total = items.Sum(t => t.Type == TransactionType.Expense ? t.Amount : -t.Amount);

        return new InvoiceDto(card.Id, card.Name, monthStart.ToString("yyyy-MM"), start, closing, due,
            total, paid, clock.Today < closing, items.Select(ToDto).ToList());
    }

    public static TransactionDto ToDto(Transaction t) => new(
        t.Id, t.AccountId, t.Account!.Name, t.CategoryId, t.Category!.Name, t.Category.Icon, t.Category.Color,
        t.Description, t.Amount, t.Type, t.Date, t.IsPaid, t.SeriesId, t.InstallmentNumber, t.InstallmentCount);

    public Task<List<Transfer>> GetTransfersAsync(Guid userId, DateOnly start, DateOnly end) =>
        db.Transfers.AsNoTracking()
            .Include(t => t.FromAccount).Include(t => t.ToAccount)
            .Where(t => t.UserId == userId && t.Date >= start && t.Date <= end)
            .OrderByDescending(t => t.Date)
            .ToListAsync();

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

    /// <summary>
    /// Orçamentos que valem no mês (RN-27): o do próprio mês ou, se não houver, o mais recente de
    /// um mês anterior marcado para repetir e cuja repetição ainda não foi parada.
    /// </summary>
    public async Task<List<BudgetDto>> GetBudgetsAsync(Guid userId, string monthKey, IEnumerable<Transaction> monthTxs)
    {
        // "yyyy-MM" ordena como texto na mesma ordem das datas.
        var candidates = await db.Budgets.AsNoTracking().Include(b => b.Category)
            .Where(b => b.UserId == userId && (b.Month == monthKey ||
                (b.Recurring && string.Compare(b.Month, monthKey) < 0 &&
                 (b.UntilMonth == null || string.Compare(monthKey, b.UntilMonth) < 0))))
            .ToListAsync();
        return candidates
            .GroupBy(b => b.CategoryId)
            .Select(g => g.MaxBy(b => b.Month)!)
            .OrderBy(b => b.Category!.Name)
            .Select(b => new BudgetDto(
                b.Id, b.CategoryId, b.Category!.Name, b.Category.Color, b.Month, b.Limit,
                monthTxs.Where(t => t.CategoryId == b.CategoryId && t.Type == TransactionType.Expense)
                    .Sum(t => t.Amount),
                b.Recurring, b.Month != monthKey))
            .ToList();
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
