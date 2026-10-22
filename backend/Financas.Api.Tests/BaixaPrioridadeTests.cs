using System.Net;
using System.Net.Http.Json;
using System.Text;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Financas.Api.Services;

namespace Financas.Api.Tests;

public class BaixaPrioridadeTests
{
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name, decimal Balance, decimal ForecastBalance);
    private record Tx(Guid Id, string Type, string CategoryName, Guid? CategoryId, string AccountName,
        Guid? DestinationAccountId, string? DestinationAccountName, decimal Amount);
    private record Budget(Guid Id, string CategoryName, string Month, decimal Limit, bool IsRecurring, bool Inherited);
    private record Dashboard(decimal Income, decimal Expenses, List<object> ExpensesByCategory, List<Budget> Budgets);
    private record IdBody(Guid Id);
    private record ErrorBody(string Error);

    private static async Task<(HttpClient c, List<Category> cats, Account carteira, Account nubank)> SetupAsync(ApiFactory f)
    {
        var c = await f.CreateUserClientAsync();
        (await c.PostAsJsonAsync("/api/accounts", new { name = "Nubank", initialBalance = 0m })).EnsureSuccessStatusCode();
        var accs = (await c.GetFromJsonAsync<List<Account>>("/api/accounts"))!;
        var cats = (await c.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        return (c, cats, accs.Single(a => a.Name == "Carteira"), accs.Single(a => a.Name == "Nubank"));
    }

    // ---------- Transferência entre contas ----------

    [Fact]
    public async Task Transferencia_move_saldo_e_nao_conta_como_receita_nem_despesa()
    {
        using var f = new ApiFactory();
        var (c, cats, carteira, nubank) = await SetupAsync(f);
        await c.PostAsJsonAsync("/api/transactions", new { accountId = carteira.Id, categoryId = cats.Single(x => x.Name == "Salário").Id,
            description = "Salário", amount = 1000m, type = "Income", date = "2026-10-05" });

        var res = await c.PostAsJsonAsync("/api/transactions", new { accountId = carteira.Id, destinationAccountId = nubank.Id,
            description = "Guardar", amount = 300m, type = "Transfer", date = "2026-10-10" });
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);

        var accs = (await c.GetFromJsonAsync<List<Account>>("/api/accounts"))!;
        Assert.Equal(700m, accs.Single(a => a.Name == "Carteira").Balance);
        Assert.Equal(300m, accs.Single(a => a.Name == "Nubank").Balance);

        var d = (await c.GetFromJsonAsync<Dashboard>("/api/dashboard?month=2026-10"))!;
        Assert.Equal(1000m, d.Income);
        Assert.Equal(0m, d.Expenses);
        Assert.Empty(d.ExpensesByCategory);

        var tx = (await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-10"))!.Single(t => t.Type == "Transfer");
        Assert.Equal("Transferência", tx.CategoryName);
        Assert.Null(tx.CategoryId);
        Assert.Equal("Nubank", tx.DestinationAccountName);
    }

    [Theory]
    [InlineData("mesma conta", "A conta de origem e a de destino precisam ser diferentes.")]
    [InlineData("sem destino", "Escolha a conta de destino da transferência.")]
    [InlineData("com categoria", "Transferência não tem categoria.")]
    public async Task Transferencia_invalida_e_recusada(string caso, string erro)
    {
        using var f = new ApiFactory();
        var (c, cats, carteira, nubank) = await SetupAsync(f);
        object body = caso switch
        {
            "mesma conta" => new { accountId = carteira.Id, destinationAccountId = carteira.Id, amount = 10m, type = "Transfer", date = "2026-10-10" },
            "sem destino" => new { accountId = carteira.Id, amount = 10m, type = "Transfer", date = "2026-10-10" },
            _ => new { accountId = carteira.Id, destinationAccountId = nubank.Id, categoryId = cats[0].Id, amount = 10m, type = "Transfer", date = "2026-10-10" },
        };
        var res = await c.PostAsJsonAsync("/api/transactions", body);
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
        Assert.Equal(erro, (await res.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
    }

    // ---------- Idempotência (reprocessamento do agente) ----------

    [Fact]
    public async Task Mesmo_external_id_nao_duplica_lancamento_nem_em_paralelo()
    {
        using var f = new ApiFactory();
        var (c, cats, carteira, _) = await SetupAsync(f);
        var body = new { accountId = carteira.Id, categoryId = cats.Single(x => x.Name == "Lazer").Id, description = "Cinema",
            amount = 40m, type = "Expense", date = "2026-10-10", externalId = "call_abc123" };

        var first = await c.PostAsJsonAsync("/api/transactions", body);
        var again = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => c.PostAsJsonAsync("/api/transactions", body)));

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        var id = (await first.Content.ReadFromJsonAsync<IdBody>())!.Id;
        foreach (var r in again)
        {
            Assert.Equal(HttpStatusCode.OK, r.StatusCode);
            Assert.Equal(id, (await r.Content.ReadFromJsonAsync<IdBody>())!.Id);
        }
        Assert.Single(await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-10") ?? []);
    }

    // ---------- Orçamentos recorrentes ----------

    private static Task<List<Budget>> BudgetsAsync(HttpClient c, string month) =>
        c.GetFromJsonAsync<List<Budget>>($"/api/budgets?month={month}")!;

    [Fact]
    public async Task Orcamento_recorrente_vale_nos_meses_seguintes_ate_ser_trocado_ou_interrompido()
    {
        using var f = new ApiFactory();
        var (c, cats, _, _) = await SetupAsync(f);
        var lazer = cats.Single(x => x.Name == "Lazer").Id;

        var created = await c.PostAsJsonAsync("/api/budgets", new { categoryId = lazer, month = "2026-10", limit = 300m, isRecurring = true });
        var id = (await created.Content.ReadFromJsonAsync<IdBody>())!.Id;

        var nov = Assert.Single(await BudgetsAsync(c, "2026-11"));
        Assert.Equal((300m, true, true), (nov.Limit, nov.IsRecurring, nov.Inherited));
        Assert.Empty(await BudgetsAsync(c, "2026-09"));

        // Exceção só em dezembro: janeiro volta ao recorrente.
        await c.PostAsJsonAsync("/api/budgets", new { categoryId = lazer, month = "2026-12", limit = 500m, isRecurring = false });
        Assert.Equal(500m, Assert.Single(await BudgetsAsync(c, "2026-12")).Limit);
        Assert.Equal(300m, Assert.Single(await BudgetsAsync(c, "2027-01")).Limit);

        // "Parar de repetir" vendo fevereiro: some de fevereiro em diante, meses anteriores intactos.
        Assert.Equal(HttpStatusCode.NoContent, (await c.DeleteAsync($"/api/budgets/{id}?month=2027-02")).StatusCode);
        Assert.Empty(await BudgetsAsync(c, "2027-02"));
        Assert.Empty(await BudgetsAsync(c, "2027-06"));
        Assert.Equal(300m, Assert.Single(await BudgetsAsync(c, "2027-01")).Limit);
        Assert.Equal(300m, Assert.Single(await BudgetsAsync(c, "2026-10")).Limit);
    }

    [Fact]
    public async Task Interromper_nao_faz_um_recorrente_mais_antigo_reaparecer()
    {
        using var f = new ApiFactory();
        var (c, cats, _, _) = await SetupAsync(f);
        var lazer = cats.Single(x => x.Name == "Lazer").Id;

        await c.PostAsJsonAsync("/api/budgets", new { categoryId = lazer, month = "2026-07", limit = 500m, isRecurring = true });
        var sep = await c.PostAsJsonAsync("/api/budgets", new { categoryId = lazer, month = "2026-09", limit = 800m, isRecurring = true });
        Assert.Equal(800m, Assert.Single(await BudgetsAsync(c, "2026-10")).Limit);

        var sepId = (await sep.Content.ReadFromJsonAsync<IdBody>())!.Id;
        await c.DeleteAsync($"/api/budgets/{sepId}?month=2026-11");

        Assert.Empty(await BudgetsAsync(c, "2026-11"));
        Assert.Equal(500m, Assert.Single(await BudgetsAsync(c, "2026-08")).Limit);
    }

    // ---------- Descrições opcionais no DeepSeek ----------

    private class CaptureHandler : HttpMessageHandler
    {
        public List<string> Bodies { get; } = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage req, CancellationToken ct)
        {
            Bodies.Add(await req.Content!.ReadAsStringAsync(ct));
            const string content = """{"summary":"ok","alerts":[],"tips":[],"potentialSavings":0,"healthScore":50}""";
            var json = System.Text.Json.JsonSerializer.Serialize(new { choices = new[] { new { message = new { role = "assistant", content } } } });
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
        }
    }

    [Fact]
    public async Task Usuario_pode_gerar_insights_sem_enviar_descricoes()
    {
        var deepSeek = new CaptureHandler();
        using var f = new ApiFactory { Settings = { ["DeepSeek:ApiKey"] = "fake" } };
        using var withFake = f.WithWebHostBuilder(b => b.ConfigureTestServices(s =>
            s.AddHttpClient<DeepSeekClient>().ConfigurePrimaryHttpMessageHandler(() => deepSeek)));
        var c = withFake.CreateClient();
        var reg = await c.PostAsJsonAsync("/api/auth/register", new { name = "X", email = "x@teste.com", password = "123456" });
        var token = (await reg.Content.ReadFromJsonAsync<ApiFactory.AuthBody>())!.Token;
        c.DefaultRequestHeaders.Authorization = new("Bearer", token);
        var cats = (await c.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var acc = (await c.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        await c.PostAsJsonAsync("/api/transactions", new { accountId = acc.Id, categoryId = cats.Single(x => x.Name == "Saúde").Id,
            description = "Consulta Dra Fulana psiquiatra", amount = 350m, type = "Expense", date = "2026-10-10" });

        Assert.Equal(HttpStatusCode.OK, (await c.PostAsJsonAsync("/api/insights", new { month = "2026-10", includeDescriptions = false })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await c.PostAsJsonAsync("/api/insights", new { month = "2026-10" })).StatusCode);

        Assert.DoesNotContain("Fulana", deepSeek.Bodies[0]);
        Assert.Contains("Saúde", System.Text.RegularExpressions.Regex.Unescape(deepSeek.Bodies[0]));
        Assert.Contains("Fulana", deepSeek.Bodies[1]); // padrão continua enviando
    }

    // ---------- Limite de login entre réplicas ----------

    [Fact]
    public async Task Limite_de_login_e_compartilhado_entre_replicas()
    {
        var db = $"financas_test_{Guid.NewGuid():N}";
        using var a = new ApiFactory { DatabaseName = db };
        using var b = new ApiFactory { DatabaseName = db, OwnsDatabase = false };
        a.CreateClient();
        var ca = a.CreateClient();
        var cb = b.CreateClient();

        for (var i = 0; i < 6; i++) await ca.PostAsJsonAsync("/api/auth/login", new { email = "ninguem@teste.com", password = "x" });
        for (var i = 0; i < 4; i++) await cb.PostAsJsonAsync("/api/auth/login", new { email = "ninguem@teste.com", password = "x" });

        var blockedA = await ca.PostAsJsonAsync("/api/auth/login", new { email = "ninguem@teste.com", password = "x" });
        var blockedB = await cb.PostAsJsonAsync("/api/auth/login", new { email = "ninguem@teste.com", password = "x" });
        Assert.Equal(HttpStatusCode.TooManyRequests, blockedA.StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, blockedB.StatusCode);
        Assert.True(int.Parse(blockedA.Headers.GetValues("Retry-After").Single()) is > 0 and <= 60);

        // Próximo minuto: libera.
        a.Clock.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(HttpStatusCode.Unauthorized,
            (await ca.PostAsJsonAsync("/api/auth/login", new { email = "ninguem@teste.com", password = "x" })).StatusCode);
    }
}
