using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Endpoints;

public static class AuthEndpoints
{
    public static void MapAuthEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/auth").WithTags("Auth");

        g.MapPost("/register", async (RegisterRequest req, AppDbContext db, TokenService tokens) =>
        {
            var email = req.Email.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(req.Name) || !email.Contains('@') || req.Password.Length < 6)
                return Results.BadRequest(new { error = "Nome, e-mail válido e senha (mín. 6 caracteres) são obrigatórios." });
            if (await db.Users.AnyAsync(u => u.Email == email))
                return Results.Conflict(new { error = "E-mail já cadastrado." });

            var user = new User { Name = req.Name.Trim(), Email = email, PasswordHash = BCrypt.Net.BCrypt.HashPassword(req.Password) };
            db.Users.Add(user);
            db.Categories.AddRange(AppDbContext.DefaultCategories(user.Id));
            db.Accounts.Add(new Account { UserId = user.Id, Name = "Carteira", Color = "#4CAF50" });
            await db.SaveChangesAsync();

            return Results.Ok(new AuthResponse(tokens.Create(user), user.Name, user.Email));
        });

        g.MapPost("/login", async (LoginRequest req, AppDbContext db, TokenService tokens) =>
        {
            var email = req.Email.Trim().ToLowerInvariant();
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email);
            if (user is null || !BCrypt.Net.BCrypt.Verify(req.Password, user.PasswordHash))
                return Results.Unauthorized();
            return Results.Ok(new AuthResponse(tokens.Create(user), user.Name, user.Email));
        });
    }
}
