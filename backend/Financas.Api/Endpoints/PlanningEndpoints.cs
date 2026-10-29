using System.Globalization;
using System.Security.Claims;
using System.Text;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Endpoints;

/// <summary>Metas (RN-36), sequência e conquistas (RN-37), exportação (RN-40) e erros do app.</summary>
public static class PlanningEndpoints
{
    public static void MapPlanningEndpoints(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api").RequireAuthorization();

        // ---------- Metas ----------
        var goals = api.MapGroup("/goals").WithTags("Metas");
        goals.MapGet("/", async (ClaimsPrincipal user, AppDbContext db, AppClock clock) =>
            (await db.Goals.AsNoTracking().Where(g => g.UserId == user.ProfileId()).OrderBy(g => g.CreatedAt).ToListAsync())
                .Select(g => ToDto(g, clock.Today)));

        goals.MapPost("/", async (GoalRequest req, ClaimsPrincipal user, AppDbContext db, AppClock clock) =>
        {
            if (Validate(req) is { } error) return error;
            var g = new Goal { UserId = user.ProfileId(), CreatedAt = clock.UtcNow };
            Apply(g, req);
            db.Goals.Add(g);
            await db.SaveChangesAsync();
            return Results.Created($"/api/goals/{g.Id}", ToDto(g, clock.Today));
        });

        goals.MapPut("/{id:guid}", async (Guid id, GoalRequest req, ClaimsPrincipal user, AppDbContext db, AppClock clock) =>
        {
            var g = await db.Goals.FirstOrDefaultAsync(x => x.Id == id && x.UserId == user.ProfileId());
            if (g is null) return Results.NotFound();
            if (Validate(req) is { } error) return error;
            Apply(g, req);
            await db.SaveChangesAsync();
            return Results.Ok(ToDto(g, clock.Today));
        });

        // Guardar (valor positivo) ou retirar (negativo). O guardado nunca fica abaixo de zero.
        goals.MapPost("/{id:guid}/deposit", async (Guid id, GoalDepositRequest req, ClaimsPrincipal user, AppDbContext db, AppClock clock) =>
        {
            var g = await db.Goals.FirstOrDefaultAsync(x => x.Id == id && x.UserId == user.ProfileId());
            if (g is null) return Results.NotFound();
            if (req.Amount == 0 || Math.Abs(req.Amount) >= 1_000_000_000m)
                return Results.BadRequest(new { error = "Informe um valor válido." });
            g.Saved = Math.Max(0, g.Saved + req.Amount);
            await db.SaveChangesAsync();
            return Results.Ok(ToDto(g, clock.Today));
        });

        goals.MapDelete("/{id:guid}", async (Guid id, ClaimsPrincipal user, AppDbContext db) =>
            await db.Goals.Where(x => x.Id == id && x.UserId == user.ProfileId()).ExecuteDeleteAsync() > 0
                ? Results.NoContent() : Results.NotFound());

        // ---------- Sequência e conquistas ----------
        api.MapGet("/me/progress", async (ClaimsPrincipal user, AppDbContext db, AppClock clock, FinanceService finance) =>
        {
            var uid = user.ProfileId();
            var created = await db.Transactions.AsNoTracking().Where(t => t.UserId == uid)
                .Select(t => t.CreatedAt).ToListAsync();
            var days = created.Select(clock.LocalDate).ToHashSet();
            var (streak, best) = Streaks(days, clock.Today);

            // Mês passado: dentro de todos os orçamentos e taxa de economia.
            var (lastStart, lastEnd, lastKey) = finance.ParseMonth(clock.Today.AddMonths(-1).ToString("yyyy-MM"));
            var lastTxs = await finance.GetTransactionsAsync(uid, lastStart, lastEnd);
            var lastBudgets = await finance.GetBudgetsAsync(uid, lastKey, lastTxs);
            var income = lastTxs.Where(t => t.Type == TransactionType.Income).Sum(t => t.Amount);
            var expenses = lastTxs.Where(t => t.Type == TransactionType.Expense).Sum(t => t.Amount);

            var goalsList = await db.Goals.AsNoTracking().Where(g => g.UserId == uid).ToListAsync();
            var hasBudget = await db.Budgets.AnyAsync(b => b.UserId == uid);
            var hasCard = await db.Accounts.AnyAsync(a => a.UserId == uid && a.Kind == AccountKind.CreditCard);

            AchievementDto A(string id, string title, string desc, string icon, bool ok) => new(id, title, desc, icon, ok);
            // Conquistas de contagem mostram quanto falta (o app desenha um anel de progresso).
            AchievementDto N(string id, string title, string desc, string icon, int current, int target) =>
                new(id, title, desc, icon, current >= target, Math.Min(current, target), target);
            var achievements = new List<AchievementDto>
            {
                A("first_entry", "Primeiro passo", "Registre seu primeiro lançamento.", "flag", created.Count >= 1),
                N("entries_50", "Organizado", "Registre 50 lançamentos.", "receipt_long", created.Count, 50),
                N("streak_7", "Uma semana firme", "Registre algo 7 dias seguidos.", "local_fire_department", best, 7),
                N("streak_30", "Hábito formado", "Registre algo 30 dias seguidos.", "whatshot", best, 30),
                A("budget_set", "Com limite", "Crie seu primeiro orçamento.", "savings", hasBudget),
                A("under_budget", "Dentro do combinado",
                    "Termine um mês dentro de todos os orçamentos.", "verified",
                    lastBudgets.Count > 0 && lastBudgets.All(b => b.Spent <= b.Limit)),
                A("saver_20", "Poupador", "Guarde 20% do que ganhou no mês passado.", "trending_up",
                    income > 0 && (income - expenses) / income >= 0.2m),
                A("goal_created", "Sonho com data", "Crie uma meta de economia.", "flag_circle", goalsList.Count > 0),
                A("goal_reached", "Meta batida!", "Complete uma meta.", "emoji_events",
                    goalsList.Any(g => g.Target > 0 && g.Saved >= g.Target)),
                A("card_added", "Cartão sob controle", "Cadastre um cartão de crédito.", "credit_card", hasCard),
            };
            return new ProgressDto(streak, best, days.Contains(clock.Today), achievements);
        }).WithTags("Perfil");

        // ---------- Exportação ----------
        // RN-40: todos os lançamentos e transferências em CSV para planilhas (separador ";" e vírgula
        // decimal, como o Excel em português abre sem configurar nada).
        api.MapGet("/export/transactions.csv", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.ProfileId();
            var txs = await db.Transactions.AsNoTracking().Include(t => t.Account).Include(t => t.Category)
                .Where(t => t.UserId == uid).OrderBy(t => t.Date).ToListAsync();
            var transfers = await db.Transfers.AsNoTracking().Include(t => t.FromAccount).Include(t => t.ToAccount)
                .Where(t => t.UserId == uid).OrderBy(t => t.Date).ToListAsync();

            var pt = CultureInfo.GetCultureInfo("pt-BR");
            var sb = new StringBuilder("Data;Descrição;Categoria;Conta;Tipo;Valor;Situação\r\n");
            var rows = txs.Select(t => (t.Date, Row: new[]
                {
                    t.Date.ToString("dd/MM/yyyy", pt), t.Description, t.Category!.Name, t.Account!.Name,
                    t.Type == TransactionType.Income ? "Receita" : "Despesa",
                    (t.Type == TransactionType.Income ? t.Amount : -t.Amount).ToString("0.00", pt),
                    t.IsPaid ? "Pago" : "Pendente",
                }))
                .Concat(transfers.Select(t => (t.Date, Row: new[]
                {
                    t.Date.ToString("dd/MM/yyyy", pt), t.Description, "Transferência",
                    $"{t.FromAccount!.Name} → {t.ToAccount!.Name}", "Transferência",
                    t.Amount.ToString("0.00", pt), t.IsPaid ? "Pago" : "Pendente",
                })))
                .OrderBy(r => r.Date);
            foreach (var (_, row) in rows) sb.Append(string.Join(';', row.Select(Csv))).Append("\r\n");

            // BOM para o Excel reconhecer UTF-8 (acentos).
            var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(sb.ToString())).ToArray();
            return Results.File(bytes, "text/csv; charset=utf-8", "economizze-lancamentos.csv");
        }).WithTags("Exportação");

        // ---------- Erros do app ----------
        // O app envia exceções não tratadas; ficam no log da API (sem dados financeiros, só a mensagem
        // e a pilha). Aceita sem login para registrar falhas da tela de entrada. Limite global por IP.
        app.MapPost("/api/client-errors", (ClientErrorRequest req, ILoggerFactory logs) =>
        {
            static string Cut(string? s, int max) => s is null ? "" : s.Length <= max ? s : s[..max];
            logs.CreateLogger("ClientErrors").LogWarning(
                "Erro no app ({Platform} {Version}): {Message}\n{Stack}",
                OneLine(Cut(req.Platform, 20)), OneLine(Cut(req.Version, 20)), OneLine(Cut(req.Message, 500)),
                Indented(Cut(req.Stack, 4000)));
            return Results.NoContent();
        }).WithTags("Erros do app");
    }

    // Rota de erros do app, sem login: sem quebras de linha e caracteres de controle, ninguém forja
    // linhas falsas no log. A pilha mantém as quebras (é texto de várias linhas), com recuo em cada uma.
    public static string OneLine(string s) => new(s.Select(c => char.IsControl(c) ? ' ' : c).ToArray());
    public static string Indented(string s) => "  " + string.Join("\n  ", s.Replace("\r", "").Split('\n').Select(OneLine));

    /// <summary>
    /// Sequência atual: dias seguidos com registro terminando hoje (ou ontem, se hoje ainda não teve
    /// registro, para não zerar de manhã). Melhor sequência: a maior já feita.
    /// </summary>
    public static (int Current, int Best) Streaks(IReadOnlySet<DateOnly> days, DateOnly today)
    {
        var best = 0;
        foreach (var d in days)
        {
            if (days.Contains(d.AddDays(-1))) continue; // só começa a contar no início de uma sequência
            var len = 1;
            while (days.Contains(d.AddDays(len))) len++;
            best = Math.Max(best, len);
        }
        var end = days.Contains(today) ? today : today.AddDays(-1);
        var current = 0;
        while (days.Contains(end.AddDays(-current))) current++;
        return (current, best);
    }

    private static string Csv(string value)
    {
        // Evita injeção de fórmula ao abrir no Excel (= + @ no início). O "-" fica livre para os valores negativos.
        if (value.Length > 0 && "=+@".Contains(value[0])) value = "'" + value;
        return value.Contains(';') || value.Contains('"') || value.Contains('\n')
            ? "\"" + value.Replace("\"", "\"\"") + "\"" : value;
    }

    private static IResult? Validate(GoalRequest req)
    {
        var name = (req.Name ?? "").Trim();
        if (name.Length == 0) return Results.BadRequest(new { error = "Dê um nome para a meta." });
        if (name.Length > 60) return Results.BadRequest(new { error = "O nome pode ter no máximo 60 caracteres." });
        if (req.Target <= 0 || req.Target >= 1_000_000_000m) return Results.BadRequest(new { error = "Informe quanto quer juntar." });
        return Appearance.Validate(req.Color, req.Icon);
    }

    private static void Apply(Goal g, GoalRequest req)
    {
        g.Name = req.Name.Trim(); g.Target = req.Target; g.Deadline = req.Deadline;
        g.Icon = req.Icon ?? g.Icon; g.Color = req.Color ?? g.Color;
    }

    /// <summary>Progresso e quanto guardar por mês para chegar no prazo (contando o mês atual).</summary>
    public static GoalDto ToDto(Goal g, DateOnly today)
    {
        decimal? monthly = null;
        var missing = g.Target - g.Saved;
        if (g.Deadline is { } d && missing > 0)
        {
            var months = Math.Max(1, (d.Year - today.Year) * 12 + d.Month - today.Month + 1);
            monthly = Math.Ceiling(missing / months * 100) / 100;
        }
        return new GoalDto(g.Id, g.Name, g.Target, g.Saved, g.Deadline, g.Icon, g.Color,
            g.Target <= 0 ? 0 : Math.Min(1, (double)(g.Saved / g.Target)), monthly);
    }
}
