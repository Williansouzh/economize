using System.Security.Claims;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Endpoints;

public static class FinanceEndpoints
{
    public static void MapFinanceEndpoints(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api").RequireAuthorization();

        // ---------- Dashboard ----------
        api.MapGet("/dashboard", (string? month, ClaimsPrincipal user, FinanceService finance) =>
            finance.GetDashboardAsync(user.UserId(), month)).WithTags("Dashboard");

        // ---------- Contas ----------
        var accounts = api.MapGroup("/accounts").WithTags("Contas");
        accounts.MapGet("/", (ClaimsPrincipal user, FinanceService finance) => finance.GetAccountsAsync(user.UserId()));

        accounts.MapPost("/", async (AccountRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var a = new Account { UserId = user.UserId(), Name = req.Name, InitialBalance = req.InitialBalance, Color = req.Color ?? "#4CAF50", Icon = req.Icon ?? "account_balance_wallet" };
            db.Accounts.Add(a);
            await db.SaveChangesAsync();
            return Results.Created($"/api/accounts/{a.Id}", new AccountDto(a.Id, a.Name, a.InitialBalance, a.InitialBalance, a.InitialBalance, a.Color, a.Icon));
        });

        accounts.MapPut("/{id:guid}", async (Guid id, AccountRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var a = await db.Accounts.FirstOrDefaultAsync(x => x.Id == id && x.UserId == user.UserId());
            if (a is null) return Results.NotFound();
            a.Name = req.Name; a.InitialBalance = req.InitialBalance; a.Color = req.Color ?? a.Color; a.Icon = req.Icon ?? a.Icon;
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        accounts.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
            await db.Accounts.Where(x => x.Id == id && x.UserId == user.UserId()).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound());

        // ---------- Categorias ----------
        var categories = api.MapGroup("/categories").WithTags("Categorias");
        categories.MapGet("/", async (ClaimsPrincipal user, AppDbContext db) =>
            await db.Categories.AsNoTracking().Where(c => c.UserId == user.UserId()).OrderBy(c => c.Name)
                .Select(c => new CategoryDto(c.Id, c.Name, c.Type, c.Icon, c.Color)).ToListAsync());

        categories.MapPost("/", async (CategoryRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var c = new Category { UserId = user.UserId(), Name = req.Name, Type = req.Type, Icon = req.Icon ?? "category", Color = req.Color ?? "#9E9E9E" };
            db.Categories.Add(c);
            await db.SaveChangesAsync();
            return Results.Created($"/api/categories/{c.Id}", new CategoryDto(c.Id, c.Name, c.Type, c.Icon, c.Color));
        });

        categories.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            if (await db.Transactions.AnyAsync(t => t.CategoryId == id && t.UserId == uid))
                return Results.Conflict(new { error = "Categoria possui transações." });
            return await db.Categories.Where(x => x.Id == id && x.UserId == uid).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound();
        });

        // ---------- Transações ----------
        var txs = api.MapGroup("/transactions").WithTags("Transações");
        txs.MapGet("/", async (string? month, ClaimsPrincipal user, FinanceService finance) =>
        {
            var (start, end, _) = finance.ParseMonth(month);
            return (await finance.GetTransactionsAsync(user.UserId(), start, end)).Select(ToDto);
        });

        txs.MapPost("/", async (TransactionRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            if (await Validate(req, uid, db) is { } error) return error;
            var t = new Transaction { UserId = uid };
            Apply(t, req);
            db.Transactions.Add(t);
            await db.SaveChangesAsync();
            return Results.Created($"/api/transactions/{t.Id}", new { t.Id });
        });

        txs.MapPut("/{id:guid}", async (Guid id, TransactionRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            var t = await db.Transactions.FirstOrDefaultAsync(x => x.Id == id && x.UserId == uid);
            if (t is null) return Results.NotFound();
            if (await Validate(req, uid, db) is { } error) return error;
            Apply(t, req);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        txs.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
            await db.Transactions.Where(x => x.Id == id && x.UserId == user.UserId()).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound());

        // ---------- Orçamentos ----------
        var budgets = api.MapGroup("/budgets").WithTags("Orçamentos");
        budgets.MapGet("/", async (string? month, ClaimsPrincipal user, FinanceService finance) =>
        {
            var (start, end, key) = finance.ParseMonth(month);
            var monthTxs = await finance.GetTransactionsAsync(user.UserId(), start, end);
            return await finance.GetBudgetsAsync(user.UserId(), key, monthTxs);
        });

        // Upsert: um limite por categoria/mês.
        budgets.MapPost("/", async (BudgetRequest req, ClaimsPrincipal user, AppDbContext db, FinanceService finance) =>
        {
            var uid = user.UserId();
            var (_, _, key) = finance.ParseMonth(req.Month);
            // Orçamento é limite de gasto: só faz sentido para categorias de despesa.
            if (!await db.Categories.AnyAsync(c => c.Id == req.CategoryId && c.UserId == uid && c.Type == TransactionType.Expense))
                return Results.BadRequest(new { error = "Escolha uma categoria de despesa." });

            if (req.Limit <= 0) return Results.BadRequest(new { error = "O limite deve ser maior que zero." });

            var b = await db.Budgets.FirstOrDefaultAsync(x => x.UserId == uid && x.CategoryId == req.CategoryId && x.Month == key);
            if (b is null) db.Budgets.Add(b = new Budget { UserId = uid, CategoryId = req.CategoryId, Month = key });
            b.Limit = req.Limit;
            b.Recurring = req.Recurring;
            b.UntilMonth = null; // salvar de novo recomeça a repetição, se ela tinha sido parada
            await db.SaveChangesAsync();
            return Results.Ok(new { b.Id });
        });

        // Sem "month", ou no próprio mês do orçamento: exclui. Num mês em que ele vale por
        // repetição (RN-27): para de repetir a partir desse mês, sem mexer nos meses anteriores.
        budgets.MapDelete("/{id:guid}", async (Guid id, string? month, ClaimsPrincipal user, AppDbContext db, FinanceService finance) =>
        {
            var b = await db.Budgets.FirstOrDefaultAsync(x => x.Id == id && x.UserId == user.UserId());
            if (b is null) return Results.NotFound();
            var key = month is null ? b.Month : finance.ParseMonth(month).Key;
            if (string.CompareOrdinal(key, b.Month) <= 0) db.Budgets.Remove(b);
            else b.UntilMonth = key;
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        // ---------- Transferências ----------
        var transfers = api.MapGroup("/transfers").WithTags("Transferências");
        transfers.MapGet("/", async (string? month, ClaimsPrincipal user, FinanceService finance) =>
        {
            var (start, end, _) = finance.ParseMonth(month);
            return (await finance.GetTransfersAsync(user.UserId(), start, end)).Select(ToDto);
        });

        transfers.MapPost("/", async (TransferRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            if (await Validate(req, uid, db) is { } error) return error;
            var t = new Transfer { UserId = uid };
            Apply(t, req);
            db.Transfers.Add(t);
            await db.SaveChangesAsync();
            return Results.Created($"/api/transfers/{t.Id}", new { t.Id });
        });

        transfers.MapPut("/{id:guid}", async (Guid id, TransferRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            var t = await db.Transfers.FirstOrDefaultAsync(x => x.Id == id && x.UserId == uid);
            if (t is null) return Results.NotFound();
            if (await Validate(req, uid, db) is { } error) return error;
            Apply(t, req);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        transfers.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
            await db.Transfers.Where(x => x.Id == id && x.UserId == user.UserId()).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound());
    }

    private static async Task<IResult?> Validate(TransferRequest req, Guid uid, AppDbContext db)
    {
        if (req.Amount <= 0) return Results.BadRequest(new { error = "Valor deve ser maior que zero." });
        if (req.Amount >= 1_000_000_000_000m) return Results.BadRequest(new { error = "Valor muito alto." });
        if ((req.Description?.Trim().Length ?? 0) > 200)
            return Results.BadRequest(new { error = "Descrição pode ter no máximo 200 caracteres." });
        if (req.FromAccountId == req.ToAccountId)
            return Results.BadRequest(new { error = "Escolha contas de origem e destino diferentes." });
        var owned = await db.Accounts.CountAsync(a => a.UserId == uid && (a.Id == req.FromAccountId || a.Id == req.ToAccountId));
        return owned == 2 ? null : Results.BadRequest(new { error = "Conta inválida." });
    }

    private static void Apply(Transfer t, TransferRequest req)
    {
        t.FromAccountId = req.FromAccountId; t.ToAccountId = req.ToAccountId; t.Amount = req.Amount;
        t.Date = req.Date; t.Description = (req.Description ?? "").Trim(); t.IsPaid = req.IsPaid;
    }

    private static TransferDto ToDto(Transfer t) => new(
        t.Id, t.FromAccountId, t.FromAccount!.Name, t.ToAccountId, t.ToAccount!.Name,
        t.Amount, t.Date, t.Description, t.IsPaid);

    private static async Task<IResult?> Validate(TransactionRequest req, Guid uid, AppDbContext db)
    {
        if (req.Amount <= 0) return Results.BadRequest(new { error = "Valor deve ser maior que zero." });
        if (req.Amount >= 1_000_000_000_000m) return Results.BadRequest(new { error = "Valor muito alto." });
        if ((req.Description?.Trim().Length ?? 0) > 200)
            return Results.BadRequest(new { error = "Descrição pode ter no máximo 200 caracteres." });
        if (!await db.Accounts.AnyAsync(a => a.Id == req.AccountId && a.UserId == uid))
            return Results.BadRequest(new { error = "Conta inválida." });
        var category = await db.Categories.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == req.CategoryId && c.UserId == uid);
        if (category is null)
            return Results.BadRequest(new { error = "Categoria inválida." });
        if (category.Type != req.Type)
            return Results.BadRequest(new { error = req.Type == TransactionType.Expense
                ? "Escolha uma categoria de despesa." : "Escolha uma categoria de receita." });
        return null;
    }

    private static void Apply(Transaction t, TransactionRequest req)
    {
        t.AccountId = req.AccountId; t.CategoryId = req.CategoryId; t.Description = (req.Description ?? "").Trim();
        t.Amount = req.Amount; t.Type = req.Type; t.Date = req.Date; t.IsPaid = req.IsPaid;
    }

    private static TransactionDto ToDto(Transaction t) => new(
        t.Id, t.AccountId, t.Account!.Name, t.CategoryId, t.Category!.Name, t.Category.Icon, t.Category.Color,
        t.Description, t.Amount, t.Type, t.Date, t.IsPaid);
}
