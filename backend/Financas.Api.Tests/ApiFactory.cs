using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Financas.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using Npgsql;

namespace Financas.Api.Tests;

/// <summary>
/// Sobe a API em memória com um banco PostgreSQL temporário por instância (criado pelas migrations).
/// Servidor: variável TEST_DATABASE_URL, ou Host=localhost;Port=5432;Username=postgres;Password=postgres.
/// </summary>
public class ApiFactory : WebApplicationFactory<Program>
{
    public const string AgentKey = "chave-do-agente-para-testes";
    public const string Password = "senha-de-teste";

    public static readonly string Server = System.Environment.GetEnvironmentVariable("TEST_DATABASE_URL")
        ?? "Host=localhost;Port=5432;Username=postgres;Password=postgres";

    /// <summary>Nome do banco. Duas factories com o mesmo nome simulam duas réplicas da API.</summary>
    public string DatabaseName { get; init; } = $"financas_test_{Guid.NewGuid():N}";

    /// <summary>Só quem cria o banco o apaga (réplicas compartilham).</summary>
    public bool OwnsDatabase { get; init; } = true;

    private string ConnectionString => new NpgsqlConnectionStringBuilder(Server) { Database = DatabaseName }.ToString();

    public string Environment { get; init; } = "Development";
    public string? JwtKey { get; init; }
    public Dictionary<string, string> Settings { get; init; } = [];

    /// <summary>Corpo de cada chamada da API ao agente (POST /internal/forget). Só com Agent:Url definida.</summary>
    public List<string> AgentCalls { get; } = [];

    /// <summary>Relógio controlado pelos testes. Padrão: 17/10/2026 15:00 UTC (12:00 em São Paulo).</summary>
    public FakeTimeProvider Clock { get; } = new(new DateTimeOffset(2026, 10, 17, 15, 0, 0, TimeSpan.Zero));

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment(Environment);
        builder.UseSetting("ConnectionStrings:Default", ConnectionString);
        builder.UseSetting("Agent:ApiKey", AgentKey);
        if (JwtKey is not null) builder.UseSetting("Jwt:Key", JwtKey);
        foreach (var (key, value) in Settings) builder.UseSetting(key, value);
        builder.ConfigureTestServices(s =>
        {
            s.AddSingleton<TimeProvider>(Clock);
            s.AddHttpClient<AgentClient>().ConfigurePrimaryHttpMessageHandler(() => new RecordingHandler(AgentCalls));
        });
    }

    public async Task<HttpClient> CreateUserClientAsync(string email = "user@teste.com")
    {
        var client = CreateClient();
        var res = await client.PostAsJsonAsync("/api/auth/register", new { name = "Usuário Teste", email, password = Password });
        res.EnsureSuccessStatusCode();
        var auth = await res.Content.ReadFromJsonAsync<AuthBody>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth!.Token);
        return client;
    }

    public HttpClient CreateAgentClient()
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Add("X-Agent-Key", AgentKey);
        return client;
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (!OwnsDatabase) return;
        NpgsqlConnection.ClearAllPools();
        using var conn = new NpgsqlConnection(new NpgsqlConnectionStringBuilder(Server) { Database = "postgres" }.ToString());
        conn.Open();
        using var cmd = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{DatabaseName}\" WITH (FORCE)", conn);
        cmd.ExecuteNonQuery();
    }

    public record AuthBody(string Token, string Name, string Email);

    /// <summary>Faz o papel do agente: guarda o que recebeu e responde 200.</summary>
    private class RecordingHandler(List<string> calls) : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            var body = await request.Content!.ReadAsStringAsync(ct);
            lock (calls) calls.Add($"{request.RequestUri!.AbsolutePath} {body}");
            return new HttpResponseMessage(HttpStatusCode.OK);
        }
    }
}
