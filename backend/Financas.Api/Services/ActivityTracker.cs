using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Services;

/// <summary>
/// RN-44: marca quando cada usuário usou o app (ou o WhatsApp, que chama a API com o token dele).
/// Grava no máximo a cada <see cref="Interval"/>, para não escrever no banco a cada requisição.
/// </summary>
public class ActivityTracker(AppDbContext db, AppClock clock)
{
    public static readonly TimeSpan Interval = TimeSpan.FromMinutes(5);

    public async Task TouchAsync(Guid userId, DateTime? lastSeenAt)
    {
        var now = clock.UtcNow;
        if (lastSeenAt is { } last && now - last < Interval) return;
        await db.Users.Where(u => u.Id == userId).ExecuteUpdateAsync(s => s.SetProperty(u => u.LastSeenAt, now));
        var today = clock.Today;
        if (lastSeenAt is { } seen && clock.LocalDate(seen) == today) return;
        await db.Database.ExecuteSqlAsync(
            $"""INSERT INTO "UserActivity" ("UserId", "Day") VALUES ({userId}, {today}) ON CONFLICT DO NOTHING""");
    }
}
