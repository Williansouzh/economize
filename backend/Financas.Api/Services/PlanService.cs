using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Services;

/// <summary>Plano da pessoa agora. <paramref name="Source"/>: "trial" (mês grátis) ou "subscription".</summary>
public record PlanInfo(bool IsPlus, string? Source, DateTime? TrialEndsAt, DateTime? PaidUntil, string? SubscriptionStatus);

/// <summary>
/// RN-51: Economizze Plus. Quem cria a conta ganha um mês grátis, sem cartão; depois, o Plus vale
/// enquanto a assinatura do Mercado Pago estiver ativa ou até o fim do período já pago (mesmo cancelada).
/// Conferido aqui, no servidor, em toda chamada que depende do plano; o app só mostra.
/// </summary>
public class PlanService(AppDbContext db, AppClock clock, IConfiguration config)
{
    public decimal MonthlyPrice => config.GetValue("Plus:MonthlyPrice", 4.00m);
    public int TrialDays => config.GetValue("Plus:TrialDays", 30);

    public async Task<PlanInfo> GetAsync(Guid userId)
    {
        var now = clock.UtcNow;
        var trialEnds = await db.Users.Where(u => u.Id == userId).Select(u => u.PlusTrialEndsAt).FirstOrDefaultAsync();
        // A assinatura mais relevante: a ativa, senão a que ainda tem período pago, senão a mais recente.
        var sub = await db.Subscriptions.AsNoTracking().Where(s => s.UserId == userId)
            .OrderByDescending(s => s.Status == "authorized")
            .ThenByDescending(s => s.PaidUntil)
            .ThenByDescending(s => s.CreatedAt)
            .FirstOrDefaultAsync();
        var paid = sub is not null && (sub.Status == "authorized" || sub.PaidUntil > now);
        var trial = trialEnds > now;
        return new PlanInfo(paid || trial, paid ? "subscription" : trial ? "trial" : null, trialEnds, sub?.PaidUntil, sub?.Status);
    }

    public async Task<bool> IsPlusAsync(Guid userId) => (await GetAsync(userId)).IsPlus;

    public static IResult PlusRequired(string feature) => Results.Json(
        new { error = $"{feature} faz parte do Economizze Plus. Assine no Perfil para liberar.", plusRequired = true },
        statusCode: StatusCodes.Status403Forbidden);
}
