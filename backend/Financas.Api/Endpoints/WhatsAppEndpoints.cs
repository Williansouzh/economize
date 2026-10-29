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
            return u is null ? Results.NotFound() : Results.Ok(new MeDto(u.Name, u.Email, u.WhatsAppPhone, admin.IsAdmin(u.Id)));
        });

        // RN-32: o app troca o token por um novo ao abrir, para quem usa não precisar entrar de novo.
        // Até 90 dias depois do login; depois disso, 401 e a pessoa entra com a senha (um token roubado não dura para sempre).
        me.MapPost("/token", async (ClaimsPrincipal user, AppDbContext db, TokenService tokens) =>
        {
            var u = await db.Users.FindAsync(user.UserId());
            if (u is null) return Results.NotFound();
            return tokens.Renew(u, user) is { } token
                ? Results.Ok(new AuthResponse(token, u.Name, u.Email))
                : Results.Json(new { error = "Sua sessão venceu. Entre de novo com a sua senha." }, statusCode: StatusCodes.Status401Unauthorized);
        });

        // RN-32: "Sair de todos os aparelhos" invalida todos os tokens já emitidos, inclusive o atual.
        me.MapDelete("/sessions", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            await db.Users.Where(u => u.Id == uid)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.TokenVersion, u => u.TokenVersion + 1));
            return Results.NoContent();
        });

        me.MapPost("/whatsapp-code", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            var u = await db.Users.FindAsync(user.UserId());
            if (u is null) return Results.NotFound();
            await IssueLinkCodeAsync(db, u, () => RandomNumberGenerator.GetInt32(100000, 1000000).ToString());
            return Results.Ok(new LinkCodeDto(u.WhatsAppLinkCode!, u.WhatsAppLinkCodeExpiresAt!.Value));
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
                // Um pedido de cada vez por usuário (excluir e começar do zero ao mesmo tempo).
                await db.Database.LockUserAsync(uid);
                await DeleteAllProfilesAsync(db, uid);
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
                // Sem o lock, dois "começar do zero" juntos deixavam 2 Carteiras e as categorias em dobro:
                // o segundo apagava antes de o primeiro gravar o padrão. Assim o segundo espera e refaz.
                if (!await db.Database.LockUserAsync(uid)) return Results.NotFound();
                await DeleteAllProfilesAsync(db, uid);
                db.Categories.AddRange(AppDbContext.DefaultCategories(uid));
                db.Accounts.Add(new Account { UserId = uid, Name = "Carteira", Color = "#0C7A68" });
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
            // O número vem da Meta, só com dígitos (e não pode colidir com a linha do teto geral).
            if (req.Phone is not { Length: > 0 and <= 20 } || !req.Phone.All(char.IsAsciiDigit))
                return Results.BadRequest(new { error = "Número inválido." });
            if (await limiter.IsBlockedAsync(req.Phone))
                return Results.Json(new { error = "Muitas tentativas erradas. Aguarde 30 minutos e gere um novo código no app." },
                    statusCode: StatusCodes.Status429TooManyRequests);

            // O código é gasto num UPDATE só: com o mesmo código vindo de dois números ao mesmo tempo,
            // um vincula e o outro recebe "código inválido".
            var code = req.Code.Trim();
            await using var tx = await db.Database.BeginTransactionAsync();
            var claimed = await db.Database.SqlQuery<Guid>($"""
                UPDATE "Users" SET "WhatsAppLinkCode" = NULL, "WhatsAppLinkCodeExpiresAt" = NULL
                WHERE "WhatsAppLinkCode" = {code} AND "WhatsAppLinkCodeExpiresAt" > {DateTime.UtcNow}
                RETURNING "Id" AS "Value"
                """).ToListAsync();
            if (claimed is not [var userId])
            {
                await tx.RollbackAsync();
                await limiter.RegisterFailureAsync(req.Phone);
                return Results.BadRequest(new { error = "Código inválido ou expirado. Gere um novo código no app e tente de novo." });
            }

            // Um número só pode estar ligado a uma conta.
            await db.Users.Where(x => x.WhatsAppPhone == req.Phone && x.Id != userId)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.WhatsAppPhone, (string?)null));
            try
            {
                await db.Users.Where(x => x.Id == userId).ExecuteUpdateAsync(s => s.SetProperty(x => x.WhatsAppPhone, req.Phone));
            }
            catch (Exception e) when (e.IsUniqueViolation())
            {
                // Outra conta vinculou este número no mesmo instante. O código volta a valer (rollback).
                await tx.RollbackAsync();
                return Results.Conflict(new { error = "Esse número acabou de ser vinculado a outra conta. Tente de novo." });
            }
            await tx.CommitAsync();
            await limiter.ResetAsync(req.Phone);
            var name = await db.Users.Where(x => x.Id == userId).Select(x => x.Name).FirstAsync();
            return Results.Ok(new { Name = name });
        });

        // Troca o número por um JWT do usuário, curto (15 min) e só para as rotas que o agente usa (AgentTokenScope).
        agent.MapPost("/token", async (AgentTokenRequest req, AppDbContext db, TokenService tokens) =>
        {
            var u = await db.Users.FirstOrDefaultAsync(x => x.WhatsAppPhone == req.Phone);
            return u is null
                ? Results.NotFound(new { error = "Número não vinculado." })
                : Results.Ok(new AuthResponse(tokens.Create(u, agent: true), u.Name, u.Email));
        });
    }

    /// <summary>
    /// Grava um código de vinculação novo. Dois códigos ativos iguais mandariam o número para a conta
    /// errada: o índice único recusa o repetido e outro é sorteado.
    /// </summary>
    public static async Task IssueLinkCodeAsync(AppDbContext db, User u, Func<string> nextCode)
    {
        for (var attempt = 1; ; attempt++)
        {
            u.WhatsAppLinkCode = nextCode();
            u.WhatsAppLinkCodeExpiresAt = DateTime.UtcNow.AddMinutes(10);
            try
            {
                await db.SaveChangesAsync();
                return;
            }
            catch (DbUpdateException e) when (attempt < 5 && e.IsUniqueViolation(DbErrors.LinkCode)) { }
        }
    }

    /// <summary>Apaga os dados financeiros do usuário e dos perfis de empresa dele (RN-47), e os próprios perfis.</summary>
    private static async Task DeleteAllProfilesAsync(AppDbContext db, Guid uid)
    {
        var business = await db.Profiles.Where(p => p.OwnerId == uid).Select(p => p.Id).ToListAsync();
        foreach (var id in business.Prepend(uid))
        {
            await DeleteFinancialDataAsync(db, id);
            await db.AiCache.Where(x => x.ProfileId == id).ExecuteDeleteAsync();
        }
        await db.Profiles.Where(p => p.OwnerId == uid).ExecuteDeleteAsync();
    }

    // Ordem das chaves estrangeiras: lançamentos antes das categorias (exclusão restrita).
    public static async Task DeleteFinancialDataAsync(AppDbContext db, Guid uid)
    {
        await db.Transactions.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Transfers.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Budgets.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Accounts.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Categories.Where(x => x.UserId == uid).ExecuteDeleteAsync();
        await db.Goals.Where(x => x.UserId == uid).ExecuteDeleteAsync();
    }
}
