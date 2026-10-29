using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Financas.Api.Services;

/// <summary>
/// Limite de login, cadastro e recuperação de senha por IP (RN-26), contado no PostgreSQL para valer
/// igual em todas as réplicas: com 3 réplicas continuam sendo 10 tentativas por minuto, e não 30.
/// </summary>
public class AuthRateLimiter(AppDbContext db, TimeProvider time, IConfiguration config)
{
    private int Limit => config.GetValue("RateLimit:AuthPerMinute", 10);

    /// <summary>Conta a requisição. Devolve null se pode seguir, ou os segundos até a próxima janela.</summary>
    public Task<int?> TryAcquireAsync(string key, CancellationToken ct = default) => TryAcquireAsync(key, Limit, 1, ct);

    /// <summary>Mesma contagem com limite e janela próprios (ex.: códigos de senha por e-mail, por hora).</summary>
    public async Task<int?> TryAcquireAsync(string key, int limit, int windowMinutes, CancellationToken ct = default)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var window = DateTime.UnixEpoch.AddMinutes(Math.Floor((now - DateTime.UnixEpoch).TotalMinutes / windowMinutes) * windowMinutes);

        var conn = (NpgsqlConnection)db.Database.GetDbConnection();
        var opened = conn.State != System.Data.ConnectionState.Open;
        if (opened) await conn.OpenAsync(ct);
        try
        {
            // Incremento atômico: duas réplicas contando ao mesmo tempo não perdem tentativas.
            await using var cmd = new NpgsqlCommand("""
                INSERT INTO "RateLimitCounters" ("Key", "WindowStart", "Count") VALUES (@key, @window, 1)
                ON CONFLICT ("Key", "WindowStart") DO UPDATE SET "Count" = "RateLimitCounters"."Count" + 1
                RETURNING "Count"
                """, conn);
            cmd.Parameters.AddWithValue("key", key);
            cmd.Parameters.AddWithValue("window", window);
            var count = (int)(await cmd.ExecuteScalarAsync(ct))!;

            // Limpeza ocasional das janelas antigas.
            if (Random.Shared.Next(100) == 0)
            {
                await using var cleanup = new NpgsqlCommand(
                    "DELETE FROM \"RateLimitCounters\" WHERE \"WindowStart\" < @old", conn);
                // Duas horas: cobre também as janelas de uma hora.
                cleanup.Parameters.AddWithValue("old", now.AddHours(-2));
                await cleanup.ExecuteNonQueryAsync(ct);
            }

            return count <= limit ? null : Math.Max(1, (int)Math.Ceiling((window.AddMinutes(windowMinutes) - now).TotalSeconds));
        }
        finally
        {
            if (opened) await conn.CloseAsync();
        }
    }
}

/// <summary>Aplica o <see cref="AuthRateLimiter"/> por IP nas rotas de /api/auth.</summary>
public class AuthRateLimitFilter(AuthRateLimiter limiter) : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext ctx, EndpointFilterDelegate next)
    {
        var http = ctx.HttpContext;
        var ip = http.Connection.RemoteIpAddress?.ToString() ?? "desconhecido";
        if (await limiter.TryAcquireAsync($"auth:{ip}", http.RequestAborted) is { } retryAfter)
        {
            http.Response.Headers.RetryAfter = retryAfter.ToString();
            return Results.Json(new { error = "Muitas requisições. Aguarde um minuto e tente de novo." },
                statusCode: StatusCodes.Status429TooManyRequests);
        }
        return await next(ctx);
    }
}
