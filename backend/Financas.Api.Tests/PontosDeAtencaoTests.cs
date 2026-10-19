using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

public class PontosDeAtencaoTests
{
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name, decimal Balance, decimal ForecastBalance);
    private record Dashboard(decimal TotalBalance, decimal ForecastBalance, decimal Income, decimal Expenses,
        decimal MonthResult, decimal PendingIncome, decimal PendingExpenses);
    private record ErrorBody(string Error);

    private static async Task AddAsync(HttpClient client, string category, string type, decimal amount,
        string date, bool isPaid = true)
    {
        var cats = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var acc = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        var res = await client.PostAsJsonAsync("/api/transactions", new
        {
            accountId = acc.Id, categoryId = cats.Single(c => c.Name == category).Id,
            description = category, amount, type, date, isPaid,
        });
        res.EnsureSuccessStatusCode();
    }

    // ---------- Saldo atual × previsto ----------

    [Fact]
    public async Task Saldo_atual_ignora_pendentes_e_datas_futuras_e_o_previsto_inclui_ate_o_fim_do_mes()
    {
        using var factory = new ApiFactory(); // hoje = 17/10/2026
        var client = await factory.CreateUserClientAsync();

        await AddAsync(client, "Salário", "Income", 1000m, "2026-10-05");                 // pago, passado
        await AddAsync(client, "Moradia", "Expense", 300m, "2026-10-20", isPaid: false);  // a pagar este mês
        await AddAsync(client, "Freelance", "Income", 200m, "2026-10-25");               // pago, mas data futura
        await AddAsync(client, "Lazer", "Expense", 50m, "2026-11-03");                   // mês que vem

        var d = (await client.GetFromJsonAsync<Dashboard>("/api/dashboard?month=2026-10"))!;
        Assert.Equal(1000m, d.TotalBalance);                  // só o que já aconteceu
        Assert.Equal(1000m - 300m + 200m, d.ForecastBalance);  // tudo até 31/10, sem novembro
        Assert.Equal(300m, d.PendingExpenses);
        Assert.Equal(0m, d.PendingIncome);
        Assert.Equal(1200m - 300m, d.MonthResult);            // resultado do mês continua com pendentes

        var nov = (await client.GetFromJsonAsync<Dashboard>("/api/dashboard?month=2026-11"))!;
        Assert.Equal(1000m, nov.TotalBalance);                // saldo atual não depende do mês
        Assert.Equal(1000m - 300m + 200m - 50m, nov.ForecastBalance);
    }

    [Fact]
    public async Task Hoje_segue_o_fuso_de_Sao_Paulo_e_nao_o_do_servidor()
    {
        using var factory = new ApiFactory();
        // 18/10 01:00 UTC = 17/10 22:00 em São Paulo.
        factory.Clock.SetUtcNow(new DateTimeOffset(2026, 10, 18, 1, 0, 0, TimeSpan.Zero));
        var client = await factory.CreateUserClientAsync();

        await AddAsync(client, "Salário", "Income", 100m, "2026-10-18");

        var acc = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        Assert.Equal(0m, acc.Balance);           // dia 18 ainda não chegou no Brasil
        Assert.Equal(100m, acc.ForecastBalance);

        factory.Clock.Advance(TimeSpan.FromHours(3)); // 18/10 01:00 em São Paulo
        acc = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        Assert.Equal(100m, acc.Balance);
    }

    // ---------- Rate limit ----------

    [Fact]
    public async Task Login_e_limitado_a_10_tentativas_por_minuto()
    {
        using var factory = new ApiFactory();
        await factory.CreateUserClientAsync("alvo@teste.com"); // 1ª chamada em /api/auth
        var client = factory.CreateClient();

        for (var i = 0; i < 9; i++)
        {
            var res = await client.PostAsJsonAsync("/api/auth/login", new { email = "alvo@teste.com", password = $"errada{i}" });
            Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
        }

        var blocked = await client.PostAsJsonAsync("/api/auth/login", new { email = "alvo@teste.com", password = ApiFactory.Password });
        Assert.Equal(HttpStatusCode.TooManyRequests, blocked.StatusCode);
        Assert.StartsWith("Muitas requisições", (await blocked.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
        Assert.True(blocked.Headers.Contains("Retry-After"));
    }

    [Fact]
    public async Task Rotas_comuns_sao_limitadas_por_usuario()
    {
        using var factory = new ApiFactory { Settings = { ["RateLimit:ApiPerMinute"] = "5" } };
        var ana = await factory.CreateUserClientAsync("ana@teste.com");
        var bia = await factory.CreateUserClientAsync("bia@teste.com");

        for (var i = 0; i < 5; i++)
            Assert.Equal(HttpStatusCode.OK, (await ana.GetAsync("/api/categories")).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, (await ana.GetAsync("/api/categories")).StatusCode);

        // Outro usuário tem a própria cota.
        Assert.Equal(HttpStatusCode.OK, (await bia.GetAsync("/api/categories")).StatusCode);
    }

    // ---------- CORS ----------

    private static async Task<string?> PreflightAsync(HttpClient client, string origin)
    {
        var req = new HttpRequestMessage(HttpMethod.Options, "/api/auth/login");
        req.Headers.Add("Origin", origin);
        req.Headers.Add("Access-Control-Request-Method", "POST");
        var res = await client.SendAsync(req);
        return res.Headers.TryGetValues("Access-Control-Allow-Origin", out var v) ? v.Single() : null;
    }

    [Fact]
    public async Task Cors_em_producao_so_libera_origens_configuradas()
    {
        using var factory = new ApiFactory
        {
            Environment = "Production",
            JwtKey = new string('x', 48),
            Settings = { ["Cors:AllowedOrigins:0"] = "https://app.minhasfinancas.com.br" },
        };
        var client = factory.CreateClient();

        Assert.Equal("https://app.minhasfinancas.com.br", await PreflightAsync(client, "https://app.minhasfinancas.com.br"));
        Assert.Null(await PreflightAsync(client, "https://site-malicioso.com"));
        Assert.Null(await PreflightAsync(client, "http://localhost:3000"));
    }

    [Fact]
    public async Task Cors_em_desenvolvimento_libera_localhost()
    {
        using var factory = new ApiFactory();
        var client = factory.CreateClient();

        Assert.Equal("http://localhost:8080", await PreflightAsync(client, "http://localhost:8080"));
        Assert.Null(await PreflightAsync(client, "https://site-malicioso.com"));
    }
}
