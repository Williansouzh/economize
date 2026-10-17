using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Endpoints;

/// <summary>
/// Vinculação do WhatsApp e rotas usadas pelo agente de IA (serviço Python).
/// Fluxo: app gera código → usuário manda "VINCULAR 123456" ao bot → agente chama /api/agent/link.
/// </summary>
public static class WhatsAppEndpoints
{
    public static void MapWhatsAppEndpoints(this IEndpointRouteBuilder app)
    {
        // ---------- Usado pelo app (JWT do usuário) ----------
        var me = app.MapGroup("/api/me").RequireAuthorization().WithTags("Perfil");

        me.MapGet("/", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            var u = await db.Users.FindAsync(user.UserId());
            return u is null ? Results.NotFound() : Results.Ok(new MeDto(u.Name, u.Email, u.WhatsAppPhone));
        });

        me.MapPost("/whatsapp-code", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            var u = await db.Users.FindAsync(user.UserId());
            if (u is null) return Results.NotFound();
            u.WhatsAppLinkCode = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
            u.WhatsAppLinkCodeExpiresAt = DateTime.UtcNow.AddMinutes(10);
            await db.SaveChangesAsync();
            return Results.Ok(new LinkCodeDto(u.WhatsAppLinkCode, u.WhatsAppLinkCodeExpiresAt.Value));
        });

        me.MapDelete("/whatsapp", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            await db.Users.Where(u => u.Id == user.UserId())
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.WhatsAppPhone, (string?)null));
            return Results.NoContent();
        });

        // ---------- Usado pelo agente (header X-Agent-Key) ----------
        var agent = app.MapGroup("/api/agent").WithTags("Agente WhatsApp")
            .AddEndpointFilter(async (ctx, next) =>
            {
                var expected = ctx.HttpContext.RequestServices.GetRequiredService<IConfiguration>()["Agent:ApiKey"];
                var received = ctx.HttpContext.Request.Headers["X-Agent-Key"].ToString();
                if (string.IsNullOrEmpty(expected))
                    return Results.Problem("Agent:ApiKey não configurada.", statusCode: 503);
                return CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(expected), Encoding.UTF8.GetBytes(received))
                    ? await next(ctx)
                    : Results.Unauthorized();
            });

        agent.MapPost("/link", async (AgentLinkRequest req, AppDbContext db, LinkAttemptLimiter limiter) =>
        {
            if (limiter.IsBlocked(req.Phone))
                return Results.Json(new { error = "Muitas tentativas erradas. Aguarde 30 minutos e gere um novo código no app." },
                    statusCode: StatusCodes.Status429TooManyRequests);

            var code = req.Code.Trim();
            var u = await db.Users.FirstOrDefaultAsync(x =>
                x.WhatsAppLinkCode == code && x.WhatsAppLinkCodeExpiresAt > DateTime.UtcNow);
            if (u is null)
            {
                limiter.RegisterFailure(req.Phone);
                return Results.BadRequest(new { error = "Código inválido ou expirado. Gere um novo código no app e tente de novo." });
            }
            limiter.Reset(req.Phone);

            // Um número só pode estar ligado a uma conta.
            await db.Users.Where(x => x.WhatsAppPhone == req.Phone && x.Id != u.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.WhatsAppPhone, (string?)null));
            u.WhatsAppPhone = req.Phone;
            u.WhatsAppLinkCode = null;
            u.WhatsAppLinkCodeExpiresAt = null;
            await db.SaveChangesAsync();
            return Results.Ok(new { u.Name });
        });

        // Troca o número por um JWT do usuário; o agente então usa as rotas normais da API.
        agent.MapPost("/token", async (AgentTokenRequest req, AppDbContext db, TokenService tokens) =>
        {
            var u = await db.Users.FirstOrDefaultAsync(x => x.WhatsAppPhone == req.Phone);
            return u is null
                ? Results.NotFound(new { error = "Número não vinculado." })
                : Results.Ok(new AuthResponse(tokens.Create(u), u.Name, u.Email));
        });
    }
}
