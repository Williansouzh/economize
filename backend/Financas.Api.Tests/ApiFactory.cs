using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;

namespace Financas.Api.Tests;

/// <summary>Sobe a API em memória com um banco SQLite temporário por instância.</summary>
public class ApiFactory : WebApplicationFactory<Program>
{
    public const string AgentKey = "chave-do-agente-para-testes";
    private readonly string _dbPath = Path.Combine(Path.GetTempPath(), $"financas-test-{Guid.NewGuid():N}.db");

    public string Environment { get; init; } = "Development";
    public string? JwtKey { get; init; }
    public Dictionary<string, string> Settings { get; init; } = [];

    /// <summary>Relógio controlado pelos testes. Padrão: 17/10/2026 15:00 UTC (12:00 em São Paulo).</summary>
    public FakeTimeProvider Clock { get; } = new(new DateTimeOffset(2026, 10, 17, 15, 0, 0, TimeSpan.Zero));

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment(Environment);
        builder.UseSetting("ConnectionStrings:Default", $"Data Source={_dbPath}");
        builder.UseSetting("Agent:ApiKey", AgentKey);
        if (JwtKey is not null) builder.UseSetting("Jwt:Key", JwtKey);
        foreach (var (key, value) in Settings) builder.UseSetting(key, value);
        builder.ConfigureTestServices(s => s.AddSingleton<TimeProvider>(Clock));
    }

    public async Task<HttpClient> CreateUserClientAsync(string email = "user@teste.com")
    {
        var client = CreateClient();
        var res = await client.PostAsJsonAsync("/api/auth/register", new { name = "Usuário Teste", email, password = "123456" });
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
        foreach (var f in new[] { _dbPath, _dbPath + "-shm", _dbPath + "-wal" })
            try { File.Delete(f); } catch (IOException) { }
    }

    public record AuthBody(string Token, string Name, string Email);
}
