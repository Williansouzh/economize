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
            db.Accounts.Add(new Account { UserId = user.Id, Name = "Carteira", Color = "#4CAF50" });
            await db.SaveChangesAsync();
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
        // quem tem conta. O código vale 15 minutos e aceita 5 tentativas.
        g.MapPost("/forgot-password", async (ForgotPasswordRequest req, AppDbContext db, IEmailSender email,
            AppClock clock, ILogger<TokenService> log) =>
        {
            if (!email.IsConfigured)
                return Results.Json(new { error = "A recuperação de senha ainda não está disponível. Escreva para o suporte." },
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            var address = (req.Email ?? "").Trim().ToLowerInvariant();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == address);
            if (user is not null)
            {
                var code = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
                user.ResetCodeHash = HashCode(user.Id, code);
                user.ResetCodeExpiresAt = clock.UtcNow.AddMinutes(ResetMinutes);
                user.ResetAttempts = 0;
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

        g.MapPost("/reset-password", async (ResetPasswordRequest req, AppDbContext db, TokenService tokens, AppClock clock) =>
        {
            var address = (req.Email ?? "").Trim().ToLowerInvariant();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == address);
            var invalid = Results.BadRequest(new { error = "Código inválido ou vencido. Peça um novo." });
            if (user?.ResetCodeHash is null || user.ResetCodeExpiresAt < clock.UtcNow || user.ResetAttempts >= MaxResetAttempts)
                return invalid;
            if (!CryptographicOperations.FixedTimeEquals(
                    Encoding.ASCII.GetBytes(HashCode(user.Id, (req.Code ?? "").Trim())), Encoding.ASCII.GetBytes(user.ResetCodeHash)))
            {
                user.ResetAttempts++;
                await db.SaveChangesAsync();
                return invalid;
            }
            if ((req.NewPassword ?? "").Length < MinPasswordLength)
                return Results.BadRequest(new { error = $"A senha precisa ter pelo menos {MinPasswordLength} caracteres." });

            user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.NewPassword);
            user.ResetCodeHash = null;
            user.ResetCodeExpiresAt = null;
            user.ResetAttempts = 0;
            user.TokenVersion++; // quem estava com a senha antiga é desconectado (RN-32)
            await db.SaveChangesAsync();
            return Results.Ok(new AuthResponse(tokens.Create(user), user.Name, user.Email));
        });
    }

    public const int ResetMinutes = 15;
    public const int MaxResetAttempts = 5;

    private static string HashCode(Guid userId, string code) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{userId}:{code}")));
}
