using System.Security.Claims;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;

namespace Financas.Api.Services;

/// <summary>Rate limiting, CORS e cabeçalhos de proxy reverso.</summary>
public static class HttpProtection
{
    public static IServiceCollection AddHttpProtection(this IServiceCollection services, IConfiguration config, IHostEnvironment env)
    {
        var apiPerMinute = config.GetValue("RateLimit:ApiPerMinute", 300);

        services.AddRateLimiter(o =>
        {
            o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            o.OnRejected = async (ctx, ct) =>
            {
                if (ctx.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retry))
                    ctx.HttpContext.Response.Headers.RetryAfter = ((int)retry.TotalSeconds).ToString();
                await ctx.HttpContext.Response.WriteAsJsonAsync(
                    new { error = "Muitas requisições. Aguarde um minuto e tente de novo." }, ct);
            };

            // Login e cadastro têm limite próprio, contado no banco (AuthRateLimiter).
            // Este, em memória e por réplica, é só contra abuso nas demais rotas: por usuário logado (ou IP). As rotas do agente já são protegidas
            // pela X-Agent-Key e pelo limite por telefone, e concentram o tráfego de todos os usuários.
            o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(http =>
                http.Request.Path.StartsWithSegments("/api/agent")
                    ? RateLimitPartition.GetNoLimiter("agent")
                    : RateLimitPartition.GetFixedWindowLimiter(
                        http.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? $"ip:{ClientIp(http)}",
                        _ => new FixedWindowRateLimiterOptions
                        {
                            PermitLimit = apiPerMinute,
                            Window = TimeSpan.FromMinutes(1),
                        }));
        });

        // O app mobile não usa CORS (não é navegador). CORS só libera front-ends web listados.
        var allowed = config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
        services.AddCors(o => o.AddDefaultPolicy(p => p
            .SetIsOriginAllowed(origin => allowed.Contains(origin, StringComparer.OrdinalIgnoreCase)
                                          || (env.IsDevelopment() && IsLocalhost(origin)))
            .AllowAnyHeader()
            .AllowAnyMethod()));

        // Atrás de nginx/Caddy/Cloudflare o IP real vem em X-Forwarded-For.
        // Só ligue se a API não puder ser acessada diretamente, senão o cabeçalho pode ser forjado.
        services.Configure<ForwardedHeadersOptions>(o =>
        {
            o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
            o.KnownIPNetworks.Clear();
            o.KnownProxies.Clear();
        });
        return services;
    }

    public static WebApplication UseHttpProtection(this WebApplication app)
    {
        if (app.Configuration.GetValue("ReverseProxy:TrustForwardedHeaders", false))
            app.UseForwardedHeaders();
        app.UseCors();
        return app;
    }

    private static string ClientIp(HttpContext http) =>
        http.Connection.RemoteIpAddress?.ToString() ?? "desconhecido";

    private static bool IsLocalhost(string origin) =>
        Uri.TryCreate(origin, UriKind.Absolute, out var uri) && (uri.IsLoopback || uri.Host == "localhost");
}
