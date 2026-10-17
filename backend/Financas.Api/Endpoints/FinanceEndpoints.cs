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
            var a = new Account { UserId = user.UserId(), Name = req.Name, InitialBalance = req.InitialBalance, Color = req.Color ?? "#4CAF50" };
            db.Accounts.Add(a);
            await db.SaveChangesAsync();
            return Results.Created($"/api/accounts/{a.Id}", new AccountDto(a.Id, a.Name, a.InitialBalance, a.InitialBalance, a.InitialBalance, a.Color));
        });

        accounts.MapPut("/{id:guid}", async (Guid id, AccountRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var a = await db.Accounts.FirstOrDefaultAsync(x => x.Id == id && x.UserId == user.UserId());
            if (a is null) return Results.NotFound();
            a.Name = req.Name; a.InitialBalance = req.InitialBalance; a.Color = req.Color ?? a.Color;
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

            var b = await db.Budgets.FirstOrDefaultAsync(x => x.UserId == uid && x.CategoryId == req.CategoryId && x.Month == key);
            if (b is null) db.Budgets.Add(b = new Budget { UserId = uid, CategoryId = req.CategoryId, Month = key });
            b.Limit = req.Limit;
            await db.SaveChangesAsync();
            return Results.Ok(new { b.Id });
        });

        budgets.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
            await db.Budgets.Where(x => x.Id == id && x.UserId == user.UserId()).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound());
    }

    private static async Task<IResult?> Validate(TransactionRequest req, Guid uid, AppDbContext db)
    {
        if (req.Amount <= 0) return Results.BadRequest(new { error = "Valor deve ser maior que zero." });
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
        t.AccountId = req.AccountId; t.CategoryId = req.CategoryId; t.Description = req.Description.Trim();
        t.Amount = req.Amount; t.Type = req.Type; t.Date = req.Date; t.IsPaid = req.IsPaid;
    }

    private static TransactionDto ToDto(Transaction t) => new(
        t.Id, t.AccountId, t.Account!.Name, t.CategoryId, t.Category!.Name, t.Category.Icon, t.Category.Color,
        t.Description, t.Amount, t.Type, t.Date, t.IsPaid);
}
