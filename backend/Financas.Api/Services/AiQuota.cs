using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Financas.Api.Services;

/// <summary>
/// Cota diária de uso da IA por usuário (RN-48), somando os perfis pessoal e de empresa:
/// 20 perguntas no chat, 10 análises do mês geradas (análises que vêm do cache não contam) e
/// 60 mensagens ao assistente do WhatsApp e 10 extratos em PDF lidos na importação, que também usam a IA.
/// O dia vira à meia-noite no fuso do app. Contado no PostgreSQL para valer em todas as réplicas.
/// </summary>
public class AiQuota(AppDbContext db, AppClock clock, IConfiguration config)
{
    public const string Chat = "chat";
    public const string Insights = "insights";
    public const string WhatsApp = "whatsapp";
    public const string Import = "import";

    public int Limit(string kind) => kind switch
    {
        Chat => config.GetValue("Ai:ChatPerDay", 20),
        WhatsApp => config.GetValue("Ai:WhatsAppPerDay", 60),
        Import => config.GetValue("Ai:ImportPerDay", 10),
        _ => config.GetValue("Ai:InsightsPerDay", 10),
    };

    public async Task<int> UsedAsync(Guid userId, string kind) =>
        await db.AiUsage.Where(x => x.UserId == userId && x.Day == clock.Today && x.Kind == kind)
            .Select(x => x.Count).FirstOrDefaultAsync();

    /// <summary>Reserva um uso. Devolve quantos restam depois dele, ou null se a cota do dia acabou.</summary>
    public async Task<int?> TryUseAsync(Guid userId, string kind, CancellationToken ct = default)
    {
        var limit = Limit(kind);
        // Incremento atômico que não passa do limite: duas perguntas ao mesmo tempo não furam a cota.
        var count = await ScalarAsync("""
            INSERT INTO "AiUsage" ("UserId", "Day", "Kind", "Count") VALUES (@user, @day, @kind, 1)
            ON CONFLICT ("UserId", "Day", "Kind") DO UPDATE SET "Count" = "AiUsage"."Count" + 1
                WHERE "AiUsage"."Count" < @limit
            RETURNING "Count"
            """, userId, kind, limit, ct);
        return count is null ? null : limit - count.Value;
    }

    /// <summary>Devolve o uso quando a IA falhou: o usuário não perde a pergunta.</summary>
    public Task RefundAsync(Guid userId, string kind) =>
        db.AiUsage.Where(x => x.UserId == userId && x.Day == clock.Today && x.Kind == kind && x.Count > 0)
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.Count, x => x.Count - 1));

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

    private async Task<int?> ScalarAsync(string sql, Guid userId, string kind, int limit, CancellationToken ct)
    {
        var conn = (NpgsqlConnection)db.Database.GetDbConnection();
        var opened = conn.State != System.Data.ConnectionState.Open;
        if (opened) await conn.OpenAsync(ct);
        try
        {
            await using var cmd = new NpgsqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("user", userId);
            cmd.Parameters.AddWithValue("day", clock.Today);
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
