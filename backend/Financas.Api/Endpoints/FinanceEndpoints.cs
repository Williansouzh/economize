using System.Security.Claims;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.AspNetCore.Mvc;
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
            finance.GetDashboardAsync(user.ProfileId(), month)).WithTags("Dashboard");

        // ---------- Contas ----------
        var accounts = api.MapGroup("/accounts").WithTags("Contas");
        accounts.MapGet("/", (ClaimsPrincipal user, FinanceService finance) => finance.GetAccountsAsync(user.ProfileId()));

        accounts.MapPost("/", async (AccountRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            if (Validate(req) is { } error) return error;
            var a = new Account { UserId = user.ProfileId() };
            Apply(a, req);
            db.Accounts.Add(a);
            await db.SaveChangesAsync();
            return Results.Created($"/api/accounts/{a.Id}", new AccountDto(a.Id, a.Name, a.InitialBalance, a.InitialBalance,
                a.InitialBalance, a.Color, a.Icon, a.Kind, a.CreditLimit, a.ClosingDay, a.DueDay));
        });

        accounts.MapPut("/{id:guid}", async (Guid id, AccountRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var a = await db.Accounts.FirstOrDefaultAsync(x => x.Id == id && x.UserId == user.ProfileId());
            if (a is null) return Results.NotFound();
            if (Validate(req) is { } error) return error;
            Apply(a, req);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        // RN-35: fatura do cartão que fecha no mês informado (sem mês: a que está aberta hoje).
        accounts.MapGet("/{id:guid}/invoice", async (Guid id, string? month, ClaimsPrincipal user, FinanceService finance) =>
            await finance.GetInvoiceAsync(user.ProfileId(), id, month) is { } invoice
                ? Results.Ok(invoice)
                : Results.NotFound(new { error = "Cartão não encontrado." }));

        accounts.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
            await db.Accounts.Where(x => x.Id == id && x.UserId == user.ProfileId()).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound());

        // ---------- Categorias ----------
        var categories = api.MapGroup("/categories").WithTags("Categorias");
        categories.MapGet("/", async (ClaimsPrincipal user, AppDbContext db) =>
            await db.Categories.AsNoTracking().Where(c => c.UserId == user.ProfileId()).OrderBy(c => c.Name)
                .Select(c => new CategoryDto(c.Id, c.Name, c.Type, c.Icon, c.Color)).ToListAsync());

        categories.MapPost("/", async (CategoryRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            if (await ValidateCategory(req, uid, null, db) is { } error) return error;
            var c = new Category { UserId = uid, Name = req.Name.Trim(), Type = req.Type, Icon = req.Icon ?? "category", Color = req.Color ?? "#668E93" };
            db.Categories.Add(c);
            // A checagem acima é a resposta rápida; quem garante o nome único é o índice do banco.
            try { await db.SaveChangesAsync(); }
            catch (DbUpdateException e) when (e.IsUniqueViolation(DbErrors.CategoryName)) { return DuplicateCategory(); }
            return Results.Created($"/api/categories/{c.Id}", new CategoryDto(c.Id, c.Name, c.Type, c.Icon, c.Color));
        });

        // RN-31: nome, ícone e cor sempre podem mudar; o tipo, só se a categoria não tiver
        // lançamentos nem orçamentos (senão uma despesa viraria receita no histórico).
        categories.MapPut("/{id:guid}", async (Guid id, CategoryRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            var c = await db.Categories.FirstOrDefaultAsync(x => x.Id == id && x.UserId == uid);
            if (c is null) return Results.NotFound();
            if (await ValidateCategory(req, uid, id, db) is { } error) return error;
            if (req.Type != c.Type &&
                (await db.Transactions.AnyAsync(t => t.CategoryId == id) || await db.Budgets.AnyAsync(b => b.CategoryId == id)))
                return Results.BadRequest(new { error = "Não dá para trocar o tipo de uma categoria que já tem lançamentos ou orçamentos." });
            c.Name = req.Name.Trim(); c.Type = req.Type; c.Icon = req.Icon ?? c.Icon; c.Color = req.Color ?? c.Color;
            try { await db.SaveChangesAsync(); }
            catch (DbUpdateException e) when (e.IsUniqueViolation(DbErrors.CategoryName)) { return DuplicateCategory(); }
            return Results.Ok(new CategoryDto(c.Id, c.Name, c.Type, c.Icon, c.Color));
        });

        categories.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            if (await db.Transactions.AnyAsync(t => t.CategoryId == id && t.UserId == uid))
                return Results.Conflict(new { error = "Essa categoria tem lançamentos. Mude a categoria deles ou apague-os antes." });
            return await db.Categories.Where(x => x.Id == id && x.UserId == uid).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound();
        });

        // ---------- Transações ----------
        var txs = api.MapGroup("/transactions").WithTags("Transações");
        txs.MapGet("/", async (string? month, ClaimsPrincipal user, FinanceService finance) =>
        {
            var (start, end, _) = finance.ParseMonth(month);
            return (await finance.GetTransactionsAsync(user.ProfileId(), start, end)).Select(FinanceService.ToDto);
        });

        // RN-34: busca em todos os meses por texto (descrição ou categoria), categoria, conta e tipo.
        txs.MapGet("/search", async (string? q, Guid? categoryId, Guid? accountId, TransactionType? type,
            ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            var query = db.Transactions.AsNoTracking().Include(t => t.Account).Include(t => t.Category)
                .Where(t => t.UserId == uid);
            var text = (q ?? "").Trim();
            if (text.Length > 0)
            {
                var pattern = "%" + text.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_") + "%";
                // Sem o escape explícito, o Npgsql gera ESCAPE '' e o "\" deixaria de proteger % e _.
                query = query.Where(t => EF.Functions.ILike(t.Description, pattern, "\\")
                                      || EF.Functions.ILike(t.Category!.Name, pattern, "\\"));
            }
            if (categoryId is not null) query = query.Where(t => t.CategoryId == categoryId);
            if (accountId is not null) query = query.Where(t => t.AccountId == accountId);
            if (type is not null) query = query.Where(t => t.Type == type);
            var found = await query.OrderByDescending(t => t.Date).ThenByDescending(t => t.CreatedAt).Take(SearchLimit).ToListAsync();
            return found.Select(FinanceService.ToDto);
        });

        // Contas a pagar e a receber nos próximos dias (lembretes do app, RN-39).
        txs.MapGet("/upcoming", async (int? days, ClaimsPrincipal user, AppDbContext db, AppClock clock) =>
        {
            var uid = user.ProfileId();
            var today = clock.Today;
            var until = today.AddDays(Math.Clamp(days ?? 30, 1, 90));
            var found = await db.Transactions.AsNoTracking().Include(t => t.Account).Include(t => t.Category)
                .Where(t => t.UserId == uid && !t.IsPaid && t.Date >= today && t.Date <= until)
                .OrderBy(t => t.Date).Take(100).ToListAsync();
            return found.Select(FinanceService.ToDto);
        });

        // Idempotency-Key (opcional, RN-45): repetir o POST com a mesma chave devolve o lançamento já criado
        // (200 em vez de 201), mesmo com envios simultâneos.
        txs.MapPost("/", async (TransactionRequest req, [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey,
            ClaimsPrincipal user, AppDbContext db, AppClock clock) =>
        {
            var uid = user.ProfileId();
            var key = string.IsNullOrWhiteSpace(idempotencyKey) ? null : idempotencyKey.Trim();
            if (key is { Length: > 100 })
                return Results.BadRequest(new { error = "Idempotency-Key pode ter no máximo 100 caracteres." });
            if (key is not null && await FindByIdempotencyKeyAsync(db, uid, key) is { } existing)
                return Results.Ok(new { Id = existing });

            if (await Validate(req, uid, db) is { } error) return error;
            if (ValidateRepeat(req.Repeat) is { } repeatError) return repeatError;
            var created = Expand(req, uid, clock);
            created[0].IdempotencyKey = key; // numa série, a chave fica no primeiro lançamento
            db.Transactions.AddRange(created);
            try
            {
                await db.SaveChangesAsync();
            }
            catch (DbUpdateException e) when (key is not null
                && e.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
            {
                // Outra requisição com a mesma chave gravou primeiro (duas réplicas ao mesmo tempo).
                return Results.Ok(new { Id = (await FindByIdempotencyKeyAsync(db, uid, key))!.Value });
            }
            return Results.Created($"/api/transactions/{created[0].Id}", new { created[0].Id });
        });

        // scope=future: aplica a mudança também nos próximos lançamentos da mesma série (RN-33).
        // Cada um mantém a própria data e a situação (pago ou não).
        txs.MapPut("/{id:guid}", async (Guid id, string? scope, TransactionRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            var t = await db.Transactions.FirstOrDefaultAsync(x => x.Id == id && x.UserId == uid);
            if (t is null) return Results.NotFound();
            if (await Validate(req, uid, db) is { } error) return error;
            if (scope == "future" && t.SeriesId is not null)
            {
                var amount = t.InstallmentCount is null ? req.Amount : (decimal?)null; // parcela: valor de cada uma não muda em lote
                await db.Transactions
                    .Where(x => x.UserId == uid && x.SeriesId == t.SeriesId && x.Date > t.Date)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(x => x.AccountId, req.AccountId)
                        .SetProperty(x => x.CategoryId, req.CategoryId)
                        .SetProperty(x => x.Description, (req.Description ?? "").Trim())
                        .SetProperty(x => x.Type, req.Type)
                        .SetProperty(x => x.Amount, x => amount ?? x.Amount));
            }
            Apply(t, req);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        // scope=future: exclui este e os próximos da mesma série (RN-33).
        txs.MapDelete("/{id:guid}", async (Guid id, string? scope, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            var t = await db.Transactions.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.UserId == uid);
            if (t is null) return Results.NotFound();
            if (scope == "future" && t.SeriesId is not null)
                await db.Transactions.Where(x => x.UserId == uid && x.SeriesId == t.SeriesId && x.Date >= t.Date).ExecuteDeleteAsync();
            else
                await db.Transactions.Where(x => x.Id == id).ExecuteDeleteAsync();
            return Results.NoContent();
        });

        // ---------- Orçamentos ----------
        var budgets = api.MapGroup("/budgets").WithTags("Orçamentos");
        budgets.MapGet("/", async (string? month, ClaimsPrincipal user, FinanceService finance) =>
        {
            var (start, end, key) = finance.ParseMonth(month);
            var monthTxs = await finance.GetTransactionsAsync(user.ProfileId(), start, end);
            return await finance.GetBudgetsAsync(user.ProfileId(), key, monthTxs);
        });

        // Upsert: um limite por categoria/mês.
        budgets.MapPost("/", async (BudgetRequest req, ClaimsPrincipal user, AppDbContext db, FinanceService finance) =>
        {
            var uid = user.ProfileId();
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
            var b = await db.Budgets.FirstOrDefaultAsync(x => x.Id == id && x.UserId == user.ProfileId());
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
            return (await finance.GetTransfersAsync(user.ProfileId(), start, end)).Select(ToDto);
        });

        transfers.MapPost("/", async (TransferRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            if (await Validate(req, uid, db) is { } error) return error;
            var t = new Transfer { UserId = uid };
            Apply(t, req);
            db.Transfers.Add(t);
            await db.SaveChangesAsync();
            return Results.Created($"/api/transfers/{t.Id}", new { t.Id });
        });

        transfers.MapPut("/{id:guid}", async (Guid id, TransferRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            var t = await db.Transfers.FirstOrDefaultAsync(x => x.Id == id && x.UserId == uid);
            if (t is null) return Results.NotFound();
            if (await Validate(req, uid, db) is { } error) return error;
            Apply(t, req);
            await db.SaveChangesAsync();
            return Results.NoContent();
        });

        transfers.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
            await db.Transfers.Where(x => x.Id == id && x.UserId == user.ProfileId()).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound());
    }

    /// <summary>RN-31: nome obrigatório, até 40 caracteres e único entre as categorias do mesmo tipo.</summary>
    private static async Task<IResult?> ValidateCategory(CategoryRequest req, Guid uid, Guid? id, AppDbContext db)
    {
        var name = (req.Name ?? "").Trim();
        if (name.Length == 0) return Results.BadRequest(new { error = "Dê um nome para a categoria." });
        if (name.Length > 40) return Results.BadRequest(new { error = "O nome pode ter no máximo 40 caracteres." });
        if (!Enum.IsDefined(req.Type)) return Results.BadRequest(new { error = "Tipo inválido." });
        if (Appearance.Validate(req.Color, req.Icon) is { } look) return look;
        var lower = name.ToLower();
        if (await db.Categories.AnyAsync(c => c.UserId == uid && c.Type == req.Type && c.Id != id && c.Name.ToLower() == lower))
            return DuplicateCategory();
        return null;
    }

    private static IResult DuplicateCategory() => Results.Conflict(new { error = "Você já tem uma categoria com esse nome." });

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

    public const int SearchLimit = 100;
    public const int MaxRepeat = 60;

    private static IResult? ValidateRepeat(RepeatRequest? r)
    {
        if (r is null) return null;
        if (r.Kind is not ("monthly" or "installments")) return Results.BadRequest(new { error = "Repetição inválida." });
        if (r.Kind == "installments" && r.Count is < 2 or > MaxRepeat)
            return Results.BadRequest(new { error = $"Parcelas: de 2 a {MaxRepeat}." });
        if (r.Kind == "monthly" && r.Count is < 2 or > MaxRepeat)
            return Results.BadRequest(new { error = $"Repetição: de 2 a {MaxRepeat} meses." });
        return null;
    }

    /// <summary>
    /// RN-33: um lançamento vira vários, um por mês, na mesma série. Fixo: mesmo valor todo mês.
    /// Parcelado: o total é dividido e os centavos que sobram ficam na 1ª parcela. Só o primeiro segue
    /// o "pago" informado; os dos meses seguintes nascem pendentes (exceto no cartão, que é cobrado na fatura).
    /// O dia é mantido; em meses mais curtos, cai no último dia.
    /// </summary>
    private static List<Transaction> Expand(TransactionRequest req, Guid uid, AppClock clock)
    {
        var now = clock.UtcNow;
        var first = new Transaction { UserId = uid, CreatedAt = now };
        Apply(first, req);
        if (req.Repeat is not { } r) return [first];

        var seriesId = Guid.NewGuid();
        var installments = r.Kind == "installments";
        var each = installments ? Math.Floor(req.Amount / r.Count * 100) / 100 : req.Amount;
        if (each <= 0) each = 0.01m;
        var list = new List<Transaction>();
        var monthStart = new DateOnly(req.Date.Year, req.Date.Month, 1);
        for (var i = 0; i < r.Count; i++)
        {
            var t = new Transaction { UserId = uid, CreatedAt = now };
            Apply(t, req);
            t.SeriesId = seriesId;
            t.Date = FinanceService.DayOfMonth(monthStart.AddMonths(i), req.Date.Day);
            t.Amount = installments && i == 0 ? req.Amount - each * (r.Count - 1) : each;
            if (i > 0) t.IsPaid = false;
            if (installments) { t.InstallmentNumber = i + 1; t.InstallmentCount = r.Count; }
            list.Add(t);
        }
        return list;
    }

    private static IResult? Validate(AccountRequest req)
    {
        var name = (req.Name ?? "").Trim();
        if (name.Length == 0) return Results.BadRequest(new { error = "Dê um nome para a conta." });
        if (name.Length > 60) return Results.BadRequest(new { error = "O nome pode ter no máximo 60 caracteres." });
        if (!Enum.IsDefined(req.Kind)) return Results.BadRequest(new { error = "Tipo de conta inválido." });
        if (Appearance.Validate(req.Color, req.Icon) is { } look) return look;
        if (req.Kind == AccountKind.CreditCard)
        {
            if (req.ClosingDay is not (>= 1 and <= 31) || req.DueDay is not (>= 1 and <= 31))
                return Results.BadRequest(new { error = "Informe o dia de fechamento e o de vencimento da fatura (1 a 31)." });
            if (req.CreditLimit is < 0) return Results.BadRequest(new { error = "O limite não pode ser negativo." });
        }
        return null;
    }

    private static void Apply(Account a, AccountRequest req)
    {
        a.Name = req.Name.Trim(); a.InitialBalance = req.InitialBalance; a.Kind = req.Kind;
        a.Color = req.Color ?? a.Color;
        a.Icon = req.Icon ?? (req.Kind == AccountKind.CreditCard ? "credit_card" : a.Icon);
        var card = req.Kind == AccountKind.CreditCard;
        a.CreditLimit = card ? req.CreditLimit : null;
        a.ClosingDay = card ? req.ClosingDay : null;
        a.DueDay = card ? req.DueDay : null;
    }

    private static async Task<Guid?> FindByIdempotencyKeyAsync(AppDbContext db, Guid uid, string key) =>
        await db.Transactions.Where(t => t.UserId == uid && t.IdempotencyKey == key)
            .Select(t => (Guid?)t.Id).FirstOrDefaultAsync();
}
