using System.Security.Claims;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Endpoints;

/// <summary>Questionário do onboarding (RN-46), perfis pessoal e de empresa (RN-47) e as análises da situação.</summary>
public static class ProfileEndpoints
{
    public const int MaxBusinessProfiles = 2;

    public static void MapProfileEndpoints(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api").RequireAuthorization();

        // ---------- Questionário ----------
        var about = api.MapGroup("/me/about").WithTags("Perfil");
        about.MapGet("/", async (ClaimsPrincipal user, AppDbContext db, AnalysisService analysis) =>
            await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == user.UserId()) is { } u
                ? Results.Ok(ToDto(u, analysis)) : Results.NotFound());

        about.MapPut("/", async (AboutRequest req, ClaimsPrincipal user, AppDbContext db, AnalysisService analysis, AppClock clock) =>
        {
            var u = await db.Users.FirstOrDefaultAsync(x => x.Id == user.UserId());
            if (u is null) return Results.NotFound();
            var year = clock.Today.Year;
            if (req.BirthYear is { } by && (by > year - 14 || by < year - 110))
                return Results.BadRequest(new { error = "Ano de nascimento inválido." });
            var state = req.State?.Trim().ToUpperInvariant();
            if (!string.IsNullOrEmpty(state) && !IncomeBenchmark.IsState(state))
                return Results.BadRequest(new { error = "Estado inválido." });
            var sources = (req.Sources ?? []).Select(s => s.Trim().ToLowerInvariant()).Distinct().ToList();
            if (sources.Any(s => !AnalysisService.Sources.Contains(s)))
                return Results.BadRequest(new { error = "Fonte de renda inválida." });
            if (req.JobCount is < 0 or > 10) return Results.BadRequest(new { error = "Número de trabalhos inválido." });
            if (req.MonthlyIncome is < 0 or > 10_000_000) return Results.BadRequest(new { error = "Renda inválida." });
            if (req.MainGoal is { } goal && !AnalysisService.Goals.Contains(goal))
                return Results.BadRequest(new { error = "Objetivo inválido." });

            u.BirthYear = req.BirthYear;
            u.State = string.IsNullOrEmpty(state) ? null : state;
            u.IncomeSources = sources.Count == 0 ? null : string.Join(',', sources);
            u.JobCount = req.JobCount;
            u.DeclaredIncome = req.MonthlyIncome;
            u.MainGoal = req.MainGoal;
            u.AboutUpdatedAt = clock.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(ToDto(u, analysis));
        });

        // ---------- Análises ----------
        var analyses = api.MapGroup("/analysis").WithTags("Análise");
        analyses.MapGet("/initial", async (ClaimsPrincipal user, AnalysisService analysis) =>
            await analysis.InitialAsync(user.UserId()) is { } a ? Results.Ok(a) : Results.NotFound());
        analyses.MapGet("/monthly", async (string? month, ClaimsPrincipal user, AnalysisService analysis) =>
            await analysis.MonthlyAsync(user.UserId(), user.ProfileId(), month) is { } a ? Results.Ok(a) : Results.NotFound());
        analyses.MapGet("/mei", async (int? year, ClaimsPrincipal user, AnalysisService analysis, AppClock clock) =>
            user.IsBusinessProfile()
                ? Results.Ok(await analysis.MeiAsync(user.ProfileId(), year ?? clock.Today.Year))
                : Results.BadRequest(new { error = "O resumo do MEI é do perfil de empresa." }));

        // ---------- Perfis ----------
        var profiles = api.MapGroup("/profiles").WithTags("Perfis");
        profiles.MapGet("/", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            var business = await db.Profiles.AsNoTracking().Where(p => p.OwnerId == uid).OrderBy(p => p.CreatedAt).ToListAsync();
            return business.Select(ToDto).Prepend(new ProfileDto(uid, "Pessoal", ProfileKind.Personal, null, false));
        });

        profiles.MapPost("/", async (ProfileRequest req, ClaimsPrincipal user, AppDbContext db, AppClock clock) =>
        {
            if (Validate(req) is { } error) return error;
            var uid = user.UserId();
            if (await db.Profiles.CountAsync(p => p.OwnerId == uid) >= MaxBusinessProfiles)
                return Results.BadRequest(new { error = $"Você pode ter até {MaxBusinessProfiles} perfis de empresa." });
            var p = new Profile { OwnerId = uid, CreatedAt = clock.UtcNow };
            Apply(p, req);
            db.Profiles.Add(p);
            db.Categories.AddRange(AppDbContext.BusinessCategories(p.Id));
            db.Accounts.Add(new Account { UserId = p.Id, Name = "Conta da empresa", Icon = "storefront", Color = "#0B2B2E" });
            await db.SaveChangesAsync();
            return Results.Created($"/api/profiles/{p.Id}", ToDto(p));
        });

        profiles.MapPut("/{id:guid}", async (Guid id, ProfileRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var p = await db.Profiles.FirstOrDefaultAsync(x => x.Id == id && x.OwnerId == user.UserId());
            if (p is null) return Results.NotFound();
            if (Validate(req) is { } error) return error;
            Apply(p, req);
            await db.SaveChangesAsync();
            return Results.Ok(ToDto(p));
        });

        // Apaga o perfil e todos os dados dele. Pede a senha, como excluir a conta (RN-30).
        profiles.MapDelete("/{id:guid}", async (Guid id, [FromBody] DeleteAccountRequest req, ClaimsPrincipal user, AppDbContext db) =>
        {
            var uid = user.UserId();
            var u = await db.Users.AsNoTracking().FirstAsync(x => x.Id == uid);
            if (!BCrypt.Net.BCrypt.Verify(req.Password ?? "", u.PasswordHash))
                return Results.BadRequest(new { error = "Senha incorreta." });
            if (!await db.Profiles.AnyAsync(x => x.Id == id && x.OwnerId == uid)) return Results.NotFound();
            await using var tx = await db.Database.BeginTransactionAsync();
            await WhatsAppEndpoints.DeleteFinancialDataAsync(db, id);
            await db.AiCache.Where(x => x.ProfileId == id).ExecuteDeleteAsync();
            await db.Profiles.Where(x => x.Id == id).ExecuteDeleteAsync();
            await tx.CommitAsync();
            return Results.NoContent();
        });
    }

    private static AboutDto ToDto(User u, AnalysisService analysis) => new(u.BirthYear, analysis.Age(u), u.State,
        AnalysisService.SourceList(u), u.JobCount, u.DeclaredIncome, u.MainGoal, u.AboutUpdatedAt is not null);

    private static ProfileDto ToDto(Profile p) => new(p.Id, p.Name, ProfileKind.Business, p.Cnpj, p.IsMei);

    private static IResult? Validate(ProfileRequest req)
    {
        if (string.IsNullOrWhiteSpace(req.Name) || req.Name.Trim().Length > 60)
            return Results.BadRequest(new { error = "Dê um nome de até 60 letras para a empresa." });
        var cnpj = DigitsOnly(req.Cnpj);
        if (cnpj.Length > 0 && !IsValidCnpj(cnpj)) return Results.BadRequest(new { error = "CNPJ inválido." });
        return null;
    }

    private static void Apply(Profile p, ProfileRequest req)
    {
        p.Name = req.Name.Trim();
        var cnpj = DigitsOnly(req.Cnpj);
        p.Cnpj = cnpj.Length == 0 ? null : cnpj;
        p.IsMei = req.IsMei;
    }

    private static string DigitsOnly(string? s) => new((s ?? "").Where(char.IsAsciiDigit).ToArray());

    /// <summary>Confere os dois dígitos verificadores do CNPJ.</summary>
    public static bool IsValidCnpj(string digits)
    {
        if (digits.Length != 14 || digits.Distinct().Count() == 1) return false;
        int Check(int length)
        {
            int[] weights = length == 12 ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2] : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
            var sum = 0;
            for (var i = 0; i < length; i++) sum += (digits[i] - '0') * weights[i];
            var r = sum % 11;
            return r < 2 ? 0 : 11 - r;
        }
        return Check(12) == digits[12] - '0' && Check(13) == digits[13] - '0';
    }
}
