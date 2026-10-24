using System.Security.Claims;
using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Services;

/// <summary>
/// Perfil ativo da requisição (RN-47). O app manda o header <c>X-Profile</c> com o id do perfil de
/// empresa; sem o header, ou com o id do próprio usuário, vale o perfil pessoal. Um id que não é de
/// um perfil do usuário recebe 404, sem dizer se o perfil existe para outra pessoa.
/// </summary>
public static class ProfileScope
{
    public const string Header = "X-Profile";
    public const string Claim = "profile";

    /// <summary>Dono dos dados financeiros: o perfil ativo (pessoal = id do usuário).</summary>
    public static Guid ProfileId(this ClaimsPrincipal user) =>
        Guid.TryParse(user.FindFirstValue(Claim), out var id) ? id : user.UserId();

    /// <summary>Se o perfil ativo é de empresa.</summary>
    public static bool IsBusinessProfile(this ClaimsPrincipal user) => user.ProfileId() != user.UserId();

    public static IApplicationBuilder UseProfileScope(this IApplicationBuilder app) => app.Use(async (ctx, next) =>
    {
        var header = ctx.Request.Headers[Header].ToString();
        if (header.Length > 0 && ctx.User.Identity?.IsAuthenticated == true)
        {
            var userId = ctx.User.UserId();
            if (!Guid.TryParse(header, out var profileId))
            {
                await Results.BadRequest(new { error = "Perfil inválido." }).ExecuteAsync(ctx);
                return;
            }
            if (profileId != userId)
            {
                var db = ctx.RequestServices.GetRequiredService<AppDbContext>();
                if (!await db.Profiles.AnyAsync(p => p.Id == profileId && p.OwnerId == userId))
                {
                    await Results.NotFound(new { error = "Perfil não encontrado." }).ExecuteAsync(ctx);
                    return;
                }
                ctx.User.AddIdentity(new ClaimsIdentity([new Claim(Claim, profileId.ToString())]));
            }
        }
        await next();
    });
}
