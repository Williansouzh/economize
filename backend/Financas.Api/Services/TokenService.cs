using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Financas.Api.Models;
using Microsoft.IdentityModel.Tokens;

namespace Financas.Api.Services;

public class TokenService(IConfiguration config)
{
    public const string VersionClaim = "tv";
    /// <summary>Marca o token entregue ao agente do WhatsApp (veja <see cref="AgentTokenScope"/>).</summary>
    public const string ViaClaim = "via";
    public const string ViaAgent = "agent";
    /// <summary>O agente guarda o token por 10 minutos e pede outro depois.</summary>
    public static readonly TimeSpan AgentTokenLifetime = TimeSpan.FromMinutes(15);

    public string Create(User user) => Create(user, agent: false);

    /// <summary>agent: token curto e restrito às rotas que o assistente do WhatsApp usa.</summary>
    public string Create(User user, bool agent)
    {
        var jwt = config.GetSection("Jwt");
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
                .. agent ? [new Claim(ViaClaim, ViaAgent)] : Array.Empty<Claim>(),
            ],
            expires: agent ? DateTime.UtcNow.Add(AgentTokenLifetime) : DateTime.UtcNow.AddDays(jwt.GetValue("ExpirationDays", 14)),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}

public static class ClaimsExtensions
{
    public static Guid UserId(this ClaimsPrincipal user) =>
        Guid.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
