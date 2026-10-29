using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Financas.Api.Models;
using Microsoft.IdentityModel.Tokens;

namespace Financas.Api.Services;

public class TokenService(IConfiguration config, AppClock clock)
{
    public const string VersionClaim = "tv";
    /// <summary>Marca o token entregue ao agente do WhatsApp (veja <see cref="AgentTokenScope"/>).</summary>
    public const string ViaClaim = "via";
    public const string ViaAgent = "agent";
    /// <summary>O agente guarda o token por 10 minutos e pede outro depois.</summary>
    public static readonly TimeSpan AgentTokenLifetime = TimeSpan.FromMinutes(15);
    /// <summary>Quando a pessoa digitou a senha (segundos desde 1970). Renovar o token não muda.</summary>
    public const string AuthTimeClaim = "login";

    /// <summary>Token de um login novo (cadastro, senha ou recuperação de senha).</summary>
    public string Create(User user) => Create(user, agent: false);

    /// <summary>agent: token curto e restrito às rotas que o assistente do WhatsApp usa.</summary>
    public string Create(User user, bool agent) => Create(user, agent, clock.UtcNow);

    /// <summary>
    /// Renovação pelo app (RN-32): mantém a data do login. Passados <c>Jwt:SessionMaxDays</c> (90) dias
    /// dela, devolve null e a pessoa entra de novo com a senha; o token também nunca vale além desse prazo.
    /// Tokens de antes desta regra não têm a data e contam a partir da primeira renovação.
    /// </summary>
    public string? Renew(User user, ClaimsPrincipal current)
    {
        var authTime = long.TryParse(current.FindFirstValue(AuthTimeClaim), out var s)
            ? DateTime.UnixEpoch.AddSeconds(s) : clock.UtcNow;
        return clock.UtcNow >= SessionEnd(authTime) ? null : Create(user, agent: false, authTime);
    }

    private DateTime SessionEnd(DateTime authTime) => authTime.AddDays(config.GetValue("Jwt:SessionMaxDays", 90));

    private string Create(User user, bool agent, DateTime authTime)
    {
        var jwt = config.GetSection("Jwt");
        var lifetime = agent ? AgentTokenLifetime : TimeSpan.FromDays(jwt.GetValue("ExpirationDays", 14));
        var untilSessionEnd = SessionEnd(authTime) - clock.UtcNow;
        if (untilSessionEnd < lifetime) lifetime = untilSessionEnd;
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Key"]!));
        var token = new JwtSecurityToken(
            issuer: jwt["Issuer"],
            audience: jwt["Audience"],
            claims:
            [
                new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
                new Claim(ClaimTypes.Name, user.Name),
                new Claim(ClaimTypes.Email, user.Email),
                new Claim(VersionClaim, user.TokenVersion.ToString()),
                new Claim(AuthTimeClaim, ((long)(authTime - DateTime.UnixEpoch).TotalSeconds).ToString(), ClaimValueTypes.Integer64),
                .. agent ? [new Claim(ViaClaim, ViaAgent)] : Array.Empty<Claim>(),
            ],
            // DateTime.UtcNow (e não o relógio do app) porque a validação do JWT usa o relógio real.
            expires: DateTime.UtcNow.Add(lifetime),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}

public static class ClaimsExtensions
{
    public static Guid UserId(this ClaimsPrincipal user) =>
        Guid.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
