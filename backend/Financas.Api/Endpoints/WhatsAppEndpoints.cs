using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.AspNetCore.Mvc;
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

        me.MapGet("/", async (ClaimsPrincipal user, AppDbContext db, AdminAccess admin) =>
        {
            var u = await db.Users.FindAsync(user.UserId());
            return u is null ? Results.NotFound() : Results.Ok(new MeDto(u.Name, u.Email, u.WhatsAppPhone, admin.IsAdmin(u.Email)));
        });

        // RN-32: o app troca o token por um novo ao abrir, para quem usa não precisar entrar de novo.
        me.MapPost("/token", async (ClaimsPrincipal user, AppDbContext db, TokenService tokens) =>
        {
            var u = await db.Users.FindAsync(user.UserId());
            return u is null ? Results.NotFound() : Results.Ok(new AuthResponse(tokens.Create(u), u.Name, u.Email));
        });

        // RN-32: "Sair de todos os aparelhos" invalida todos os tokens já emitidos, inclusive o atual.
        me.MapDelete("/sessions", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            await db.Users.Where(u => u.Id == uid)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.TokenVersion, u => u.TokenVersion + 1));
            return Results.NoContent();
        });

        me.MapPost("/whatsapp-code",async (ClaimsPrincipal user, AppDbContext db) =>
        {
            var u = await db.Users.FindAsync(user.UserId());
            if (u is null) return Results.NotFound();
            u.WhatsAppLinkCode = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
            u.WhatsAppLinkCodeExpiresAt = DateTime.UtcNow.AddMinutes(10);
            await db.SaveChangesAsync();
            return Results.Ok(new LinkCodeDto(u.WhatsAppLinkCode, u.WhatsAppLinkCodeExpiresAt.Value));
        });

        me.MapDelete("/whatsapp", async (ClaimsPrincipal user, AppDbContext db, AgentClient agentClient) =>
        {
            var u = await db.Users.FindAsync(user.UserId());
            if (u is null) return Results.NotFound();
            var phone = u.WhatsAppPhone;
            u.WhatsAppPhone = null;
            await db.SaveChangesAsync();
            if (phone is not null) await agentClient.ForgetAsync(phone);
            return Results.NoContent();
        });

        // RN-30: exclui a conta e todos os dados dela. Pede a senha para que um token vazado
        // ou um celular desbloqueado não bastem para apagar tudo.
        me.MapDelete("/", async ([FromBody] DeleteAccountRequest req, ClaimsPrincipal user, AppDbContext db, AgentClient agentClient) =>
        {
            var uid = user.UserId();
            var u = await db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == uid);
            if (u is null) return Results.NotFound();
            if (!BCrypt.Net.BCrypt.Verify(req.Password ?? "", u.PasswordHash))
                return Results.BadRequest(new { error = "Senha incorreta." });

            await using (var tx = await db.Database.BeginTransactionAsync())
            {
                await DeleteFinancialDataAsync(db, uid);
                if (u.WhatsAppPhone is not null)
                    await db.LinkAttempts.Where(x => x.Phone == u.WhatsAppPhone).ExecuteDeleteAsync();
                await db.Users.Where(x => x.Id == uid).ExecuteDeleteAsync();
                await tx.CommitAsync();
            }
            if (u.WhatsAppPhone is not null) await agentClient.ForgetAsync(u.WhatsAppPhone);
            return Results.NoContent();
        });

        // RN-41: "começar do zero". Apaga os dados financeiros, mas mantém o cadastro e o WhatsApp;
        // a conta volta como no cadastro (categorias padrão e a Carteira). Também pede a senha.
        me.MapPost("/reset", async ([FromBody] DeleteAccountRequest req, ClaimsPrincipal user, AppDbContext db, AgentClient agentClient) =>
        {
            var uid = user.UserId();
            var u = await db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == uid);
            if (u is null) return Results.NotFound();
            if (!BCrypt.Net.BCrypt.Verify(req.Password ?? "", u.PasswordHash))
                return Results.BadRequest(new { error = "Senha incorreta." });

            await using (var tx = await db.Database.BeginTransactionAsync())
            {
                await DeleteFinancialDataAsync(db, uid);
                db.Categories.AddRange(AppDbContext.DefaultCategories(uid));
                db.Accounts.Add(new Account { UserId = uid, Name = "Carteira", Color = "#4CAF50" });
                await db.SaveChangesAsync();
                await tx.CommitAsync();
            }
            // O histórico da conversa citaria lançamentos que não existem mais.
            if (u.WhatsAppPhone is not null) await agentClient.ForgetAsync(u.WhatsAppPhone);
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
            if (await limiter.IsBlockedAsync(req.Phone))
                return Results.Json(new { error = "Muitas tentativas erradas. Aguarde 30 minutos e gere um novo código no app." },
                    statusCode: StatusCodes.Status429TooManyRequests);

            var code = req.Code.Trim();
            var u = await db.Users.FirstOrDefaultAsync(x =>
                x.WhatsAppLinkCode == code && x.WhatsAppLinkCodeExpiresAt > DateTime.UtcNow);
            if (u is null)
            {
                await limiter.RegisterFailureAsync(req.Phone);
                return Results.BadRequest(new { error = "Código inválido ou expirado. Gere um novo código no app e tente de novo." });
            }
            await limiter.ResetAsync(req.Phone);

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

    // Ordem das chaves estrangeiras: lançamentos antes das categorias (exclusão restrita).
    private static async Task DeleteFinancialDataAsync(AppDbContext db, Guid uid)
    {
        await db.Transactions.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Transfers.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Budgets.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Accounts.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Categories.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Goals.Where(x => x.UserId == uid).ExecuteDeleteAsync();
    }
}
