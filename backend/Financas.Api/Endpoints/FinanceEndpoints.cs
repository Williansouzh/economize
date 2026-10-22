using System.Security.Claims;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.EntityFrameworkCore;
using Npgsql;

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
            var externalId = string.IsNullOrWhiteSpace(req.ExternalId) ? null : req.ExternalId.Trim();
            if (externalId is { Length: > 100 })
                return Results.BadRequest(new { error = "ExternalId pode ter no máximo 100 caracteres." });

            // Idempotência: repetir o POST com a mesma chave devolve o lançamento já criado (200, não 201).
            if (externalId is not null && await FindByExternalIdAsync(db, uid, externalId) is { } existing)
                return Results.Ok(new { Id = existing });

            if (await Validate(req, uid, db) is { } error) return error;
            var t = new Transaction { UserId = uid, ExternalId = externalId };
            Apply(t, req);
            db.Transactions.Add(t);
            try
            {
                await db.SaveChangesAsync();
            }
            catch (DbUpdateException e) when (externalId is not null && e.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
            {
                // Duas réplicas recebendo a mesma chave ao mesmo tempo: a segunda devolve a da primeira.
                return Results.Ok(new { Id = (await FindByExternalIdAsync(db, uid, externalId))!.Value });
            }
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

        // Cria ou altera o orçamento da categoria a partir do mês informado.
        // Recorrente: vale também nos meses seguintes, até ser substituído ou interrompido.
        budgets.MapPost("/", async (BudgetRequest req, ClaimsPrincipal user, AppDbContext db, FinanceService finance) =>
        {
            var uid = user.UserId();
            var (_, _, key) = finance.ParseMonth(req.Month);
            if (req.Limit <= 0) return Results.BadRequest(new { error = "O limite precisa ser maior que zero." });
            // Orçamento é limite de gasto: só faz sentido para categorias de despesa.
            if (!await db.Categories.AnyAsync(c => c.Id == req.CategoryId && c.UserId == uid && c.Type == TransactionType.Expense))
                return Results.BadRequest(new { error = "Escolha uma categoria de despesa." });

            var b = await db.Budgets.FirstOrDefaultAsync(x => x.UserId == uid && x.CategoryId == req.CategoryId && x.Month == key);
            if (b is null) db.Budgets.Add(b = new Budget { UserId = uid, CategoryId = req.CategoryId, Month = key });
            b.Limit = req.Limit;
            b.IsRecurring = req.IsRecurring;
            b.UntilMonth = req.IsRecurring ? null : key;
            await db.SaveChangesAsync();
            return Results.Ok(new { b.Id });
        });

        // month = mês que o usuário está vendo.
        // - É o mês de criação (ou não foi informado): apaga o orçamento.
        // - É um mês posterior (orçamento herdado): para de repetir a partir desse mês, sem mexer nos anteriores.
        budgets.MapDelete("/{id:guid}", async (Guid id, string? month, ClaimsPrincipal user, AppDbContext db, FinanceService finance) =>
        {
            var uid = user.UserId();
            var b = await db.Budgets.FirstOrDefaultAsync(x => x.Id == id && x.UserId == uid);
            if (b is null) return Results.NotFound();

            var key = month is null ? b.Month : finance.ParseMonth(month).Key;
            if (string.CompareOrdinal(key, b.Month) <= 0)
            {
                db.Budgets.Remove(b);
            }
            else
            {
                // Encerra este e qualquer outro recorrente mais antigo da categoria que ainda valeria,
                // para um orçamento antigo não "reaparecer" no lugar do que foi interrompido.
                var previous = FinanceService.PreviousMonth(key);
                var open = await db.Budgets.Where(x => x.UserId == uid && x.CategoryId == b.CategoryId && x.IsRecurring
                        && string.Compare(x.Month, key) < 0 && (x.UntilMonth == null || string.Compare(x.UntilMonth, key) >= 0))
                    .ToListAsync();
                foreach (var o in open) o.UntilMonth = previous;
            }
            await db.SaveChangesAsync();
            return Results.NoContent();
        });
    }

    private static async Task<Guid?> FindByExternalIdAsync(AppDbContext db, Guid uid, string externalId) =>
        await db.Transactions.Where(x => x.UserId == uid && x.ExternalId == externalId)
            .Select(x => (Guid?)x.Id).FirstOrDefaultAsync();

    private static async Task<IResult?> Validate(TransactionRequest req, Guid uid, AppDbContext db)
    {
        if (req.Amount <= 0) return Results.BadRequest(new { error = "Valor deve ser maior que zero." });
        if (req.Amount >= 1_000_000_000_000m) return Results.BadRequest(new { error = "Valor muito alto." });
        if ((req.Description?.Trim().Length ?? 0) > 200)
            return Results.BadRequest(new { error = "Descrição pode ter no máximo 200 caracteres." });
        if (!await db.Accounts.AnyAsync(a => a.Id == req.AccountId && a.UserId == uid))
            return Results.BadRequest(new { error = "Conta inválida." });

        if (req.Type == TransactionType.Transfer)
        {
            if (req.DestinationAccountId is not { } dest || !await db.Accounts.AnyAsync(a => a.Id == dest && a.UserId == uid))
                return Results.BadRequest(new { error = "Escolha a conta de destino da transferência." });
            if (dest == req.AccountId)
                return Results.BadRequest(new { error = "A conta de origem e a de destino precisam ser diferentes." });
            if (req.CategoryId is not null)
                return Results.BadRequest(new { error = "Transferência não tem categoria." });
            return null;
        }

        if (req.Type is not (TransactionType.Income or TransactionType.Expense))
            return Results.BadRequest(new { error = "Tipo de lançamento inválido." });
        var category = req.CategoryId is null ? null : await db.Categories.AsNoTracking()
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
        var transfer = req.Type == TransactionType.Transfer;
        t.AccountId = req.AccountId;
        t.CategoryId = transfer ? null : req.CategoryId;
        t.DestinationAccountId = transfer ? req.DestinationAccountId : null;
        t.Description = (req.Description ?? "").Trim();
        t.Amount = req.Amount; t.Type = req.Type; t.Date = req.Date; t.IsPaid = req.IsPaid;
    }

    private static TransactionDto ToDto(Transaction t) => t.Type == TransactionType.Transfer
        ? new(t.Id, t.AccountId, t.Account!.Name, null, "Transferência", "swap_horiz", "#607D8B",
            t.Description, t.Amount, t.Type, t.Date, t.IsPaid, t.DestinationAccountId, t.DestinationAccount?.Name)
        : new(t.Id, t.AccountId, t.Account!.Name, t.CategoryId, t.Category!.Name, t.Category.Icon, t.Category.Color,
            t.Description, t.Amount, t.Type, t.Date, t.IsPaid, null, null);
}
