using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Services;

/// <summary>
/// Limita tentativas erradas de código de vinculação por número de WhatsApp (RN-24),
/// para que ninguém consiga adivinhar o código ativo de outra pessoa.
/// O contador fica no PostgreSQL: vale para todas as instâncias da API.
/// </summary>
public class LinkAttemptLimiter(AppDbContext db)
{
    public const int MaxFailures = 5;
    public const int WindowMinutes = 30;

    public Task<bool> IsBlockedAsync(string phone) => db.LinkAttempts.AnyAsync(x =>
        x.Phone == phone && x.Failures >= MaxFailures &&
        x.WindowStartsAt > DateTime.UtcNow.AddMinutes(-WindowMinutes));

    /// <summary>Incremento atômico: duas instâncias contando ao mesmo tempo não perdem falhas.
    /// A janela conta a partir da primeira falha; vencida, recomeça do zero.</summary>
    public Task RegisterFailureAsync(string phone) => db.Database.ExecuteSqlInterpolatedAsync($"""
        INSERT INTO "LinkAttempts" ("Phone", "Failures", "WindowStartsAt")
        VALUES ({phone}, 1, now())
        ON CONFLICT ("Phone") DO UPDATE SET
            "Failures" = CASE WHEN "LinkAttempts"."WindowStartsAt" <= now() - make_interval(mins => {WindowMinutes})
                              THEN 1 ELSE "LinkAttempts"."Failures" + 1 END,
            "WindowStartsAt" = CASE WHEN "LinkAttempts"."WindowStartsAt" <= now() - make_interval(mins => {WindowMinutes})
                                    THEN now() ELSE "LinkAttempts"."WindowStartsAt" END
        """);

    public Task ResetAsync(string phone) => db.LinkAttempts.Where(x => x.Phone == phone).ExecuteDeleteAsync();
}
