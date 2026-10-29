using System.Security.Cryptography;
using System.Text;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Endpoints;

public static class AuthEndpoints
{
    public const int MinPasswordLength = 8;

    public static void MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/auth").WithTags("Auth").AddEndpointFilter<AuthRateLimitFilter>();

        g.MapPost("/register", async (RegisterRequest req, AppDbContext db, TokenService tokens, AppClock clock,
            ActivityTracker activity) =>
        {
            var email = req.Email.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(req.Name) || !email.Contains('@'))
                return Results.BadRequest(new { error = "Informe o nome e um e-mail válido." });
            // RN-32: contas antigas com senha menor continuam entrando; a regra vale para senhas novas.
            if (req.Password.Length < MinPasswordLength)
                return Results.BadRequest(new { error = $"A senha precisa ter pelo menos {MinPasswordLength} caracteres." });
            if (await db.Users.AnyAsync(u => u.Email == email))
                return Results.Conflict(new { error = "E-mail já cadastrado." });

            var user = new User { Name = req.Name.Trim(), Email = email, CreatedAt = clock.UtcNow, PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password) };
            db.Users.Add(user);
            db.Categories.AddRange(AppDbContext.DefaultCategories(user.Id));
            db.Accounts.Add(new Account { UserId = user.Id, Name = "Carteira", Color = "#0C7A68" });
            // A checagem acima é a resposta rápida; dois cadastros juntos com o mesmo e-mail caem no índice único.
            try { await db.SaveChangesAsync(); }
            catch (DbUpdateException e) when (e.IsUniqueViolation()) { return Results.Conflict(new { error = "E-mail já cadastrado." }); }
            await activity.TouchAsync(user.Id, null);

            return Results.Ok(new AuthResponse(tokens.Create(user), user.Name, user.Email));
        });

        g.MapPost("/login", async (LoginRequest req, AppDbContext db, TokenService tokens, ActivityTracker activity) =>
        {
            var email = req.Email.Trim().ToLowerInvariant();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email);
            if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
                return Results.Unauthorized();
            await activity.TouchAsync(user.Id, user.LastSeenAt);
            return Results.Ok(new AuthResponse(tokens.Create(user), user.Name, user.Email));
        });

        // RN-38: "esqueci minha senha". A resposta é a mesma exista ou não o e-mail, para não revelar
        // quem tem conta. O código vale 15 minutos e aceita 5 tentativas. No máximo 3 pedidos por e-mail
        // por hora (contados mesmo para e-mail sem conta), e pedir um código novo enquanto o anterior vale
        // não devolve as tentativas: senão daria para alternar pedidos e chutes sem fim.
        g.MapPost("/forgot-password", async (ForgotPasswordRequest req, AppDbContext db, IEmailSender email,
            AppClock clock, AuthRateLimiter limiter, IConfiguration config, ILogger<TokenService> log) =>
        {
            if (!email.IsConfigured)
                return Results.Json(new { error = "A recuperação de senha ainda não está disponível. Escreva para o suporte." },
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            var address = (req.Email ?? "").Trim().ToLowerInvariant();
            var perHour = config.GetValue("RateLimit:PasswordResetPerHour", 3);
            // Hash do e-mail: a chave tem no máximo 120 caracteres e o e-mail digitado pode ser enorme.
            var key = "reset:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(address)));
            if (await limiter.TryAcquireAsync(key, perHour, 60) is not null)
                return Results.Json(new { error = $"Você já pediu {perHour} códigos na última hora. Use o último que chegou ou tente mais tarde." },
                    statusCode: StatusCodes.Status429TooManyRequests);
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == address);
            if (user is not null)
            {
                var code = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
                if (user.ResetCodeExpiresAt is null || user.ResetCodeExpiresAt < clock.UtcNow) user.ResetAttempts = 0;
                user.ResetCodeHash = HashCode(user.Id, code);
                user.ResetCodeExpiresAt = clock.UtcNow.AddMinutes(ResetMinutes);
                await db.SaveChangesAsync();
                try
                {
                    await email.SendAsync(user.Email, $"Seu código do Economizze: {code}",
                        $"Olá, {user.Name}!\n\nSeu código para criar uma nova senha no Economizze é: {code}\n\n" +
                        $"Ele vale por {ResetMinutes} minutos. Se não foi você que pediu, ignore este e-mail: " +
                        "sua senha continua a mesma.\n\nEquipe Economizze");
                }
                catch (Exception e)
                {
                    log.LogError(e, "Falha ao enviar o código de recuperação de senha");
                    return Results.Json(new { error = "Não conseguimos enviar o e-mail agora. Tente de novo em instantes." },
                        statusCode: StatusCodes.Status503ServiceUnavailable);
                }
            }
            return Results.Accepted();
        });

        // Cada tentativa é reservada no banco antes de conferir o código, e o código é gasto num UPDATE só:
        // com N pedidos ao mesmo tempo, continuam valendo 5 tentativas e o código troca a senha uma vez.
        g.MapPost("/reset-password", async (ResetPasswordRequest req, AppDbContext db, TokenService tokens, AppClock clock) =>
        {
            if ((req.NewPassword ?? "").Length < MinPasswordLength)
                return Results.BadRequest(new { error = $"A senha precisa ter pelo menos {MinPasswordLength} caracteres." });
            var address = (req.Email ?? "").Trim().ToLowerInvariant();
            var userId = await db.Users.Where(u => u.Email == address).Select(u => (Guid?)u.Id).FirstOrDefaultAsync();
            // A mesma mensagem em todos os casos, para não revelar se o e-mail tem conta.
            var invalid = Results.BadRequest(new { error = "Código inválido ou vencido. Se errou várias vezes, espere 15 minutos e peça um novo." });
            if (userId is not { } id) return invalid;

            var now = clock.UtcNow;
            var reserved = await db.Users
                .Where(u => u.Id == id && u.ResetCodeHash != null && u.ResetCodeExpiresAt > now && u.ResetAttempts < MaxResetAttempts)
                .ExecuteUpdateAsync(s => s.SetProperty(u => u.ResetAttempts, u => u.ResetAttempts + 1));
            if (reserved == 0) return invalid;

            var hash = HashCode(id, (req.Code ?? "").Trim());
            var passwordHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);
            var used = await db.Users
                .Where(u => u.Id == id && u.ResetCodeHash == hash && u.ResetCodeExpiresAt > now)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(u => u.PasswordHash, passwordHash)
                    .SetProperty(u => u.ResetCodeHash, (string?)null)
                    .SetProperty(u => u.ResetCodeExpiresAt, (DateTime?)null)
                    .SetProperty(u => u.ResetAttempts, 0)
                    .SetProperty(u => u.TokenVersion, u => u.TokenVersion + 1)); // quem estava com a senha antiga sai (RN-32)
            if (used == 0) return invalid;

            var user = await db.Users.AsNoTracking().FirstAsync(u => u.Id == id);
            return Results.Ok(new AuthResponse(tokens.Create(user), user.Name, user.Email));
        });
    }

    public const int ResetMinutes = 15;
    public const int MaxResetAttempts = 5;

    private static string HashCode(Guid userId, string code) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{userId}:{code}")));
}
