using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Financas.Api.Models;
using Microsoft.IdentityModel.Tokens;

namespace Financas.Api.Services;

public class TokenService(IConfiguration config)
{
    public const string VersionClaim = "tv";

    public string Create(User user)
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
            ],
            expires: DateTime.UtcNow.AddDays(jwt.GetValue("ExpirationDays", 14)),
            signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}

public static class ClaimsExtensions
{
    public static Guid UserId(this ClaimsPrincipal user) =>
        Guid.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
