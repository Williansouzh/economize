using System.Security.Claims;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Endpoints;

/// <summary>Painel do super admin (RN-44): quantas pessoas se cadastraram e estão usando o app.</summary>
public static class AdminEndpoints
{
    public static void MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var admin = app.MapGroup("/api/admin").RequireAuthorization().WithTags("Admin")
            .AddEndpointFilter(async (ctx, next) =>
            {
                // Confere o e-mail atual no banco, não o do token. Quem não é admin recebe 404: a rota "não existe".
                var services = ctx.HttpContext.RequestServices;
                var userId = ctx.HttpContext.User.UserId();
                var email = await services.GetRequiredService<AppDbContext>().Users
                    .Where(u => u.Id == userId).Select(u => u.Email).FirstOrDefaultAsync();
                return services.GetRequiredService<AdminAccess>().IsAdmin(email) ? await next(ctx) : Results.NotFound();
            });

        admin.MapGet("/stats", async (AppDbContext db, AppClock clock) =>
        {
            const int days = 30;
            var today = clock.Today;
            var first = today.AddDays(-(days - 1));
            var now = clock.UtcNow;
            // Margem de um dia para trás: o corte exato é feito no fuso do app, em memória.
            var signups = (await db.Users.AsNoTracking().Where(u => u.CreatedAt >= now.AddDays(-(days + 1)))
                    .Select(u => u.CreatedAt).ToListAsync())
                .Select(clock.LocalDate).Where(d => d >= first).ToList();
            var activity = await db.UserActivity.AsNoTracking().Where(a => a.Day >= first)
                .Select(a => new { a.UserId, a.Day }).ToListAsync();
            int Active(int lastDays) => activity.Where(a => a.Day > today.AddDays(-lastDays)).Select(a => a.UserId).Distinct().Count();
            int New(int lastDays) => signups.Count(d => d > today.AddDays(-lastDays));

            var chart = Enumerable.Range(0, days).Select(i => first.AddDays(i))
                .Select(d => new AdminDayDto(d, signups.Count(s => s == d), activity.Count(a => a.Day == d)))
                .ToList();
            var recent = await db.Users.AsNoTracking().OrderByDescending(u => u.CreatedAt).Take(50)
                .Select(u => new AdminUserDto(u.Name, u.Email, u.CreatedAt, u.LastSeenAt,
                    db.Transactions.Count(t => t.UserId == u.Id), u.WhatsAppPhone != null))
                .ToListAsync();

            return new AdminStatsDto(
                await db.Users.CountAsync(), New(1), New(7), New(days),
                Active(1), Active(7), Active(days),
                await db.Users.CountAsync(u => u.WhatsAppPhone != null),
                await db.Transactions.CountAsync(t => t.CreatedAt >= now.AddDays(-days)),
                chart, recent);
        });
    }
}
