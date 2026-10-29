using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Services;

/// <summary>
/// Limita tentativas erradas de código de vinculação por número de WhatsApp (RN-24),
/// para que ninguém consiga adivinhar o código ativo de outra pessoa.
/// Também há um teto somando todos os números: quem tenta de muitos números diferentes
/// não ganha tentativas extras. O contador fica no PostgreSQL: vale para todas as instâncias da API.
/// </summary>
public class LinkAttemptLimiter(AppDbContext db, IConfiguration config)
{
    public const int MaxFailures = 5;
    public const int WindowMinutes = 30;
    /// <summary>Linha que soma as falhas de todos os números (não é um telefone válido).</summary>
    public const string GlobalKey = "*";

    private int GlobalMaxFailures => config.GetValue("Agent:LinkGlobalMaxFailures", 100);

    public Task<bool> IsBlockedAsync(string phone)
    {
        var global = GlobalMaxFailures;
        return db.LinkAttempts.AnyAsync(x =>
            ((x.Phone == phone && x.Failures >= MaxFailures) || (x.Phone == GlobalKey && x.Failures >= global)) &&
            x.WindowStartsAt > DateTime.UtcNow.AddMinutes(-WindowMinutes));
    }

    public async Task RegisterFailureAsync(string phone)
    {
        await CountAsync(phone);
        await CountAsync(GlobalKey);
    }

    /// <summary>Incremento atômico: duas instâncias contando ao mesmo tempo não perdem falhas.
    /// A janela conta a partir da primeira falha; vencida, recomeça do zero.</summary>
    private Task CountAsync(string key) => db.Database.ExecuteSqlInterpolatedAsync($"""
        INSERT INTO "LinkAttempts" ("Phone", "Failures", "WindowStartsAt")
        VALUES ({key}, 1, now())
        ON CONFLICT ("Phone") DO UPDATE SET
            "Failures" = CASE WHEN "LinkAttempts"."WindowStartsAt" <= now() - make_interval(mins => {WindowMinutes})
                              THEN 1 ELSE "LinkAttempts"."Failures" + 1 END,
            "WindowStartsAt" = CASE WHEN "LinkAttempts"."WindowStartsAt" <= now() - make_interval(mins => {WindowMinutes})
                                    THEN now() ELSE "LinkAttempts"."WindowStartsAt" END
        """);

    /// <summary>Zera só o número que acertou; o teto geral continua contando.</summary>
    public Task ResetAsync(string phone) => db.LinkAttempts.Where(x => x.Phone == phone).ExecuteDeleteAsync();
}
