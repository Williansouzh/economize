using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Financas.Api.Services;

/// <summary>
/// Cota de uso da IA por usuário (RN-48), somando os perfis pessoal e de empresa. Com o Plus (RN-51):
/// 20 perguntas no chat, 10 análises do mês geradas (as que vêm do cache não contam), 60 mensagens ao
/// assistente do WhatsApp e 10 extratos em PDF por dia. No grátis: 3 perguntas por dia e 1 análise por
/// semana; WhatsApp e PDF são só do Plus. O dia vira à meia-noite no fuso do app (a semana, na segunda).
/// Contado no PostgreSQL para valer em todas as réplicas.
/// </summary>
public class AiQuota(AppDbContext db, AppClock clock, IConfiguration config, PlanService plans)
{
    public const string Chat = "chat";
    public const string Insights = "insights";
    public const string WhatsApp = "whatsapp";
    public const string Import = "import";

    /// <summary>Limite do Plus.</summary>
    public int Limit(string kind) => kind switch
    {
        Chat => config.GetValue("Ai:ChatPerDay", 20),
        WhatsApp => config.GetValue("Ai:WhatsAppPerDay", 60),
        Import => config.GetValue("Ai:ImportPerDay", 10),
        _ => config.GetValue("Ai:InsightsPerDay", 10),
    };

    /// <summary>Limite do grátis. As análises contam por semana; WhatsApp e PDF não têm.</summary>
    public int FreeLimit(string kind) => kind switch
    {
        Chat => config.GetValue("Ai:Free:ChatPerDay", 3),
        Insights => config.GetValue("Ai:Free:InsightsPerWeek", 1),
        _ => 0,
    };

    /// <summary>Limite e período (dia ou semana) que valem para a pessoa agora.</summary>
    public async Task<(int Limit, DateOnly Day, bool Plus)> RuleAsync(Guid userId, string kind)
    {
        var plus = await plans.IsPlusAsync(userId);
        var today = clock.Today;
        if (plus) return (Limit(kind), today, true);
        var day = kind == Insights ? today.AddDays(-(((int)today.DayOfWeek + 6) % 7)) : today; // segunda-feira
        return (FreeLimit(kind), day, false);
    }

    public async Task<int> LimitAsync(Guid userId, string kind) => (await RuleAsync(userId, kind)).Limit;

    public async Task<int> UsedAsync(Guid userId, string kind)
    {
        var (_, day, _) = await RuleAsync(userId, kind);
        return await db.AiUsage.Where(x => x.UserId == userId && x.Day == day && x.Kind == kind)
            .Select(x => x.Count).FirstOrDefaultAsync();
    }

    /// <summary>Reserva um uso. Devolve quantos restam depois dele, ou null se a cota acabou (ou o plano não tem).</summary>
    public async Task<int?> TryUseAsync(Guid userId, string kind, CancellationToken ct = default)
    {
        var (limit, day, _) = await RuleAsync(userId, kind);
        if (limit <= 0) return null;
        // Incremento atômico que não passa do limite: duas perguntas ao mesmo tempo não furam a cota.
        var count = await ScalarAsync("""
            INSERT INTO "AiUsage" ("UserId", "Day", "Kind", "Count") VALUES (@user, @day, @kind, 1)
            ON CONFLICT ("UserId", "Day", "Kind") DO UPDATE SET "Count" = "AiUsage"."Count" + 1
                WHERE "AiUsage"."Count" < @limit
            RETURNING "Count"
            """, userId, day, kind, limit, ct);
        return count is null ? null : limit - count.Value;
    }

    /// <summary>Devolve o uso quando a IA falhou: o usuário não perde a pergunta.</summary>
    public async Task RefundAsync(Guid userId, string kind)
    {
        var (_, day, _) = await RuleAsync(userId, kind);
        await db.AiUsage.Where(x => x.UserId == userId && x.Day == day && x.Kind == kind && x.Count > 0)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.Count, x => x.Count - 1));
    }

    /// <summary>Próxima meia-noite no fuso do app, em UTC.</summary>
    public DateTime ResetsAt
    {
        get
        {
            var now = clock.UtcNow;
            var hoursToMidnight = (clock.Today.AddDays(1).ToDateTime(TimeOnly.MinValue) - clock.LocalNow).TotalHours;
            return now.AddHours(hoursToMidnight);
        }
    }

    private async Task<int?> ScalarAsync(string sql, Guid userId, DateOnly day, string kind, int limit, CancellationToken ct)
    {
        var conn = (NpgsqlConnection)db.Database.GetDbConnection();
        var opened = conn.State != System.Data.ConnectionState.Open;
        if (opened) await conn.OpenAsync(ct);
        try
        {
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("user", userId);
            cmd.Parameters.AddWithValue("day", day);
            cmd.Parameters.AddWithValue("kind", kind);
            cmd.Parameters.AddWithValue("limit", limit);
            return await cmd.ExecuteScalarAsync(ct) is int n ? n : null;
        }
        finally
        {
            if (opened) await conn.CloseAsync();
        }
    }
}
