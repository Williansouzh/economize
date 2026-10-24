using System.Net;
using System.Net.Http.Json;
using Financas.Api.Endpoints;
using Financas.Api.Services;
using Microsoft.Extensions.DependencyInjection;

namespace Financas.Api.Tests;

/// <summary>RN-46 (questionário e análises), RN-47 (perfis pessoal e de empresa) e RN-48 (cota e cache da IA).</summary>
public class PerfisEAnaliseTests
{
    private record Profile(Guid Id, string Name, string Kind, string? Cnpj, bool IsMei);
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name);
    private record Benchmark(string AgeGroup, int Mean, int Median, string Region, int RegionMean, int? Percentile);
    private record Point(string Icon, string Tone, string Text);
    private record Mei(int Year, decimal Revenue, decimal Limit, double Percent, decimal ProjectedRevenue, decimal MonthlyRoom, int MonthsLeft, string Status);
    private record Analysis(string Kind, string Status, string Headline, string Message, double? SavingsRate,
        Benchmark? Benchmark, Mei? Mei, List<Point> Points);
    private record Chat(string Answer, int? Remaining);
    private record Quota(int ChatUsed, int ChatLimit, int ChatRemaining);
    private record Insights(string Summary, List<string> Alerts, List<string> Tips, bool Cached);

    private static async Task<Profile> CreateBusinessAsync(HttpClient c, string name = "Doces da Ana")
    {
        var res = await c.PostAsJsonAsync("/api/profiles", new { name, cnpj = "11.222.333/0001-81", isMei = true });
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);
        return (await res.Content.ReadFromJsonAsync<Profile>())!;
    }

    private static HttpRequestMessage In(Guid profile, HttpMethod method, string url, object? body = null)
    {
        var req = new HttpRequestMessage(method, url);
        req.Headers.Add("X-Profile", profile.ToString());
        if (body is not null) req.Content = JsonContent.Create(body);
        return req;
    }

    private static async Task<T> GetIn<T>(HttpClient c, Guid profile, string url)
    {
        var res = await c.SendAsync(In(profile, HttpMethod.Get, url));
        res.EnsureSuccessStatusCode();
        return (await res.Content.ReadFromJsonAsync<T>())!;
    }

    private static async Task AddAsync(HttpClient c, Guid? profile, string type, decimal amount, string date, string? category = null)
    {
        var p = profile ?? Guid.Empty;
        async Task<T> Get<T>(string url) => profile is null ? (await c.GetFromJsonAsync<T>(url))! : await GetIn<T>(c, p, url);
        var cats = await Get<List<Category>>("/api/categories");
        var acc = (await Get<List<Account>>("/api/accounts"))[0];
        var cat = cats.First(x => x.Type == type && (category is null || x.Name == category));
        var body = new { accountId = acc.Id, categoryId = cat.Id, description = "x", amount, type, date };
        var res = profile is null ? await c.PostAsJsonAsync("/api/transactions", body) : await c.SendAsync(In(p, HttpMethod.Post, "/api/transactions", body));
        res.EnsureSuccessStatusCode();
    }

    // ---------- RN-47: perfis ----------

    [Fact]
    public async Task Perfil_de_empresa_tem_contas_categorias_e_lancamentos_separados()
    {
        using var f = new ApiFactory();
        var c = await f.CreateUserClientAsync();
        var biz = await CreateBusinessAsync(c);

        var profiles = (await c.GetFromJsonAsync<List<Profile>>("/api/profiles"))!;
        Assert.Equal(["Personal", "Business"], profiles.Select(p => p.Kind));
        Assert.Equal("11222333000181", profiles[1].Cnpj);

        var bizCats = await GetIn<List<Category>>(c, biz.Id, "/api/categories");
        Assert.Contains(bizCats, x => x.Name == "DAS (imposto do MEI)");
        Assert.Contains(bizCats, x => x.Name == "Vendas");
        Assert.Equal(["Conta da empresa"], (await GetIn<List<Account>>(c, biz.Id, "/api/accounts")).Select(a => a.Name));

        await AddAsync(c, biz.Id, "Income", 5000m, "2026-10-05", "Vendas");
        await AddAsync(c, null, "Expense", 100m, "2026-10-06");

        var personalTx = (await c.GetFromJsonAsync<List<object>>("/api/transactions?month=2026-10"))!;
        var bizTx = await GetIn<List<object>>(c, biz.Id, "/api/transactions?month=2026-10");
        Assert.Single(personalTx);
        Assert.Single(bizTx);
        Assert.DoesNotContain((await c.GetFromJsonAsync<List<Account>>("/api/accounts"))!, a => a.Name == "Conta da empresa");
    }

    [Fact]
    public async Task Nao_da_para_lancar_na_empresa_usando_uma_conta_do_perfil_pessoal()
    {
        using var f = new ApiFactory();
        var c = await f.CreateUserClientAsync();
        var biz = await CreateBusinessAsync(c);
        var personalAccount = (await c.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        var bizCat = (await GetIn<List<Category>>(c, biz.Id, "/api/categories")).First(x => x.Name == "Vendas");

        var res = await c.SendAsync(In(biz.Id, HttpMethod.Post, "/api/transactions", new
        {
            accountId = personalAccount.Id, categoryId = bizCat.Id, description = "x", amount = 10m, type = "Income", date = "2026-10-05",
        }));
        Assert.False(res.IsSuccessStatusCode);
    }

    [Fact]
    public async Task Perfil_de_outra_pessoa_ou_invalido_e_recusado()
    {
        using var f = new ApiFactory();
        var ana = await f.CreateUserClientAsync("ana@teste.com");
        var bia = await f.CreateUserClientAsync("bia@teste.com");
        var anaBiz = await CreateBusinessAsync(ana);

        var foreign = await bia.SendAsync(In(anaBiz.Id, HttpMethod.Get, "/api/accounts"));
        Assert.Equal(HttpStatusCode.NotFound, foreign.StatusCode);

        var req = new HttpRequestMessage(HttpMethod.Get, "/api/accounts");
        req.Headers.Add("X-Profile", "nao-e-um-guid");
        Assert.Equal(HttpStatusCode.BadRequest, (await bia.SendAsync(req)).StatusCode);
    }

    [Fact]
    public async Task Limite_de_perfis_cnpj_invalido_e_exclusao_com_senha()
    {
        using var f = new ApiFactory();
        var c = await f.CreateUserClientAsync();
        var bad = await c.PostAsJsonAsync("/api/profiles", new { name = "X", cnpj = "11.222.333/0001-82" });
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);

        var first = await CreateBusinessAsync(c, "Um");
        await CreateBusinessAsync(c, "Dois");
        var third = await c.PostAsJsonAsync("/api/profiles", new { name = "Três" });
        Assert.Equal(HttpStatusCode.BadRequest, third.StatusCode);

        await AddAsync(c, first.Id, "Income", 100m, "2026-10-05");
        var wrong = await c.SendAsync(new HttpRequestMessage(HttpMethod.Delete, $"/api/profiles/{first.Id}") { Content = JsonContent.Create(new { password = "errada" }) });
        Assert.Equal(HttpStatusCode.BadRequest, wrong.StatusCode);
        var ok = await c.SendAsync(new HttpRequestMessage(HttpMethod.Delete, $"/api/profiles/{first.Id}") { Content = JsonContent.Create(new { password = ApiFactory.Password }) });
        Assert.Equal(HttpStatusCode.NoContent, ok.StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await c.SendAsync(In(first.Id, HttpMethod.Get, "/api/accounts"))).StatusCode);
    }

    [Fact]
    public async Task Excluir_a_conta_apaga_tambem_os_dados_da_empresa()
    {
        using var f = new ApiFactory();
        var c = await f.CreateUserClientAsync();
        var biz = await CreateBusinessAsync(c);
        await AddAsync(c, biz.Id, "Income", 100m, "2026-10-05");

        var res = await c.SendAsync(new HttpRequestMessage(HttpMethod.Delete, "/api/me") { Content = JsonContent.Create(new { password = ApiFactory.Password }) });
        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);

        using var scope = f.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<Financas.Api.Data.AppDbContext>();
        Assert.False(db.Transactions.Any(t => t.UserId == biz.Id));
        Assert.False(db.Accounts.Any(t => t.UserId == biz.Id));
        Assert.False(db.Profiles.Any());
    }

    [Fact]
    public async Task Resumo_do_mei_soma_o_faturamento_do_ano_e_avisa_do_teto()
    {
        using var f = new ApiFactory(); // hoje: 17/10/2026
        var c = await f.CreateUserClientAsync();
        var biz = await CreateBusinessAsync(c);
        await AddAsync(c, biz.Id, "Income", 60_000m, "2026-03-10", "Vendas");
        await AddAsync(c, biz.Id, "Income", 5_000m, "2026-10-10", "Serviços prestados");
        await AddAsync(c, biz.Id, "Income", 9_999m, "2025-12-10", "Vendas"); // outro ano

        var mei = await GetIn<Mei>(c, biz.Id, "/api/analysis/mei");
        Assert.Equal(65_000m, mei.Revenue);
        Assert.Equal(81_000m, mei.Limit);
        Assert.Equal(78_000m, mei.ProjectedRevenue); // 65 mil em 10 meses → 78 mil no ano
        Assert.Equal("ok", mei.Status);
        Assert.Equal(3, mei.MonthsLeft);           // outubro, novembro e dezembro
        Assert.Equal(5_333.33m, mei.MonthlyRoom);

        await AddAsync(c, biz.Id, "Income", 5_000m, "2026-10-11", "Vendas");
        Assert.Equal("atencao", (await GetIn<Mei>(c, biz.Id, "/api/analysis/mei")).Status); // 70 mil → 84 mil projetados

        var personal = await c.GetAsync("/api/analysis/mei");
        Assert.Equal(HttpStatusCode.BadRequest, personal.StatusCode);
    }

    // ---------- RN-46: questionário e análises ----------

    [Fact]
    public async Task Questionario_valida_e_alimenta_a_analise_inicial()
    {
        using var f = new ApiFactory();
        var c = await f.CreateUserClientAsync();
        var empty = (await c.GetFromJsonAsync<Analysis>("/api/analysis/initial"))!;
        Assert.Equal("sem_dados", empty.Status);

        Assert.Equal(HttpStatusCode.BadRequest, (await c.PutAsJsonAsync("/api/me/about", new { birthYear = 2020 })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.PutAsJsonAsync("/api/me/about", new { state = "XX" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.PutAsJsonAsync("/api/me/about", new { sources = new[] { "loteria" } })).StatusCode);

        var put = await c.PutAsJsonAsync("/api/me/about", new
        {
            birthYear = 1999, state = "pe", sources = new[] { "clt", "autonomo" }, jobCount = 2, monthlyIncome = 6000m, mainGoal = "reserva",
        });
        Assert.Equal(HttpStatusCode.OK, put.StatusCode);

        var a = (await c.GetFromJsonAsync<Analysis>("/api/analysis/initial"))!;
        Assert.Equal("25-29", a.Benchmark!.AgeGroup);   // 27 anos em 2026
        Assert.Equal("NE", a.Benchmark.Region);
        Assert.Equal(3104, a.Benchmark.Mean);
        Assert.InRange(a.Benchmark.Percentile!.Value, 85, 95); // R$ 6 mil fica entre os percentis 90 (5.700) e 95 (8.000) da faixa
        Assert.Equal("acima", a.Status);
        Assert.Contains(a.Points, p => p.Text.Contains("2 trabalhos"));
        Assert.Contains(a.Points, p => p.Text.Contains("18.000")); // reserva de 3 meses
    }

    [Fact]
    public async Task Analise_mensal_classifica_o_mes_pela_taxa_de_economia()
    {
        using var f = new ApiFactory();
        var c = await f.CreateUserClientAsync();
        Assert.Equal("sem_dados", (await c.GetFromJsonAsync<Analysis>("/api/analysis/monthly?month=2026-10"))!.Status);

        await AddAsync(c, null, "Income", 4000m, "2026-10-05");
        await AddAsync(c, null, "Expense", 3000m, "2026-10-06");
        var a = (await c.GetFromJsonAsync<Analysis>("/api/analysis/monthly?month=2026-10"))!;
        Assert.Equal("otimo", a.Status); // guardou 1000 de 4000: 25%
        Assert.Equal(0.25, a.SavingsRate);
    }

    [Theory]
    [InlineData(1000, 900, "bom")]
    [InlineData(1000, 700, "otimo")]
    [InlineData(1000, 950, "atencao")]
    [InlineData(1000, 1200, "critico")]
    public async Task Status_do_mes(decimal income, decimal expense, string status)
    {
        using var f = new ApiFactory();
        var c = await f.CreateUserClientAsync();
        await AddAsync(c, null, "Income", income, "2026-09-05");
        await AddAsync(c, null, "Expense", expense, "2026-09-06");
        Assert.Equal(status, (await c.GetFromJsonAsync<Analysis>("/api/analysis/monthly?month=2026-09"))!.Status);
    }

    [Fact]
    public async Task Sem_receita_lancada_usa_a_renda_do_questionario()
    {
        using var f = new ApiFactory();
        var c = await f.CreateUserClientAsync();
        await c.PutAsJsonAsync("/api/me/about", new { birthYear = 1990, monthlyIncome = 2000m });
        await AddAsync(c, null, "Expense", 1900m, "2026-10-06");
        var a = (await c.GetFromJsonAsync<Analysis>("/api/analysis/monthly?month=2026-10"))!;
        Assert.Equal("atencao", a.Status);
        Assert.Contains("renda que você informou", a.Message);
    }

    [Theory]
    [InlineData(400, 4)]     // abaixo do primeiro percentil (500)
    [InlineData(1621, 35)]   // salário mínimo: os percentis 30 a 45 são iguais, fica no meio do grupo
    [InlineData(1700, 48)]   // entre 1621 (p45) e 1750 (p50)
    [InlineData(50000, 97)]
    public void Percentil_da_renda(double income, int expected) =>
        Assert.Equal(expected, IncomeBenchmark.Percentile(
            [500, 800, 1000, 1400, 1620, 1621, 1621, 1621, 1621, 1750, 1800, 2000, 2000, 2146, 2400, 2500, 3000, 3200, 4200], income));

    [Fact]
    public void Cnpj_confere_os_digitos()
    {
        Assert.True(ProfileEndpoints.IsValidCnpj("11222333000181"));
        Assert.False(ProfileEndpoints.IsValidCnpj("11222333000182"));
        Assert.False(ProfileEndpoints.IsValidCnpj("11111111111111"));
    }

    // ---------- RN-48: cota e cache da IA ----------

    [Fact]
    public async Task Chat_tem_cota_de_20_perguntas_por_dia()
    {
        using var f = new ApiFactory { DeepSeekReply = "Você gastou uns R$ 300 com comida." };
        var c = await f.CreateUserClientAsync();

        for (var i = 1; i <= 20; i++)
        {
            var ok = await c.PostAsJsonAsync("/api/insights/chat", new { question = $"pergunta {i}" });
            Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
            Assert.Equal(20 - i, (await ok.Content.ReadFromJsonAsync<Chat>())!.Remaining);
        }
        var blocked = await c.PostAsJsonAsync("/api/insights/chat", new { question = "mais uma" });
        Assert.Equal(HttpStatusCode.TooManyRequests, blocked.StatusCode);
        Assert.Equal(20, f.DeepSeekCalls.Count);
        Assert.Equal(0, (await c.GetFromJsonAsync<Quota>("/api/insights/quota"))!.ChatRemaining);

        f.Clock.Advance(TimeSpan.FromDays(1));
        Assert.Equal(HttpStatusCode.OK, (await c.PostAsJsonAsync("/api/insights/chat", new { question = "novo dia" })).StatusCode);
    }

    [Fact]
    public async Task Cota_vale_para_a_pessoa_somando_os_perfis_e_pergunta_longa_e_recusada()
    {
        using var f = new ApiFactory { DeepSeekReply = "ok", Settings = { ["Ai:ChatPerDay"] = "2" } };
        var c = await f.CreateUserClientAsync();
        var biz = await CreateBusinessAsync(c);

        Assert.Equal(HttpStatusCode.OK, (await c.PostAsJsonAsync("/api/insights/chat", new { question = "a" })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await c.SendAsync(In(biz.Id, HttpMethod.Post, "/api/insights/chat", new { question = "b" }))).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, (await c.SendAsync(In(biz.Id, HttpMethod.Post, "/api/insights/chat", new { question = "c" }))).StatusCode);

        var longQuestion = await c.PostAsJsonAsync("/api/insights/chat", new { question = new string('a', 301) });
        Assert.Equal(HttpStatusCode.BadRequest, longQuestion.StatusCode);
    }

    [Fact]
    public async Task Analise_do_mes_vem_do_cache_enquanto_os_dados_nao_mudam_e_respeita_os_limites_de_tamanho()
    {
        var reply = """{"summary":"Mês tranquilo.","alerts":["a","b","c"],"tips":["1","2","3","4"],"potentialSavings":-5,"healthScore":140}""";
        using var f = new ApiFactory { DeepSeekReply = reply };
        var c = await f.CreateUserClientAsync();
        await AddAsync(c, null, "Expense", 100m, "2026-10-06");

        var first = (await (await c.PostAsJsonAsync("/api/insights", new { month = "2026-10" })).Content.ReadFromJsonAsync<Insights>())!;
        var second = (await (await c.PostAsJsonAsync("/api/insights", new { month = "2026-10" })).Content.ReadFromJsonAsync<Insights>())!;
        Assert.False(first.Cached);
        Assert.True(second.Cached);
        Assert.Single(f.DeepSeekCalls);
        Assert.Equal(2, first.Alerts.Count);
        Assert.Equal(3, first.Tips.Count);

        await AddAsync(c, null, "Expense", 50m, "2026-10-07");
        var third = (await (await c.PostAsJsonAsync("/api/insights", new { month = "2026-10" })).Content.ReadFromJsonAsync<Insights>())!;
        Assert.False(third.Cached);
        Assert.Equal(2, f.DeepSeekCalls.Count);
    }

    [Fact]
    public async Task Prompt_leva_o_perfil_e_a_comparacao_com_a_idade_e_pede_respostas_curtas()
    {
        using var f = new ApiFactory { DeepSeekReply = "ok" };
        var c = await f.CreateUserClientAsync();
        await c.PutAsJsonAsync("/api/me/about", new { birthYear = 1996, monthlyIncome = 3000m, sources = new[] { "clt" } });
        var biz = await CreateBusinessAsync(c);

        await c.PostAsJsonAsync("/api/insights/chat", new { question = "como estou?" });
        await c.SendAsync(In(biz.Id, HttpMethod.Post, "/api/insights/chat", new { question = "e a empresa?" }));

        var personal = System.Text.RegularExpressions.Regex.Unescape(f.DeepSeekCalls[0]);
        var business = System.Text.RegularExpressions.Regex.Unescape(f.DeepSeekCalls[1]);
        Assert.Contains("Perfil: PESSOAL", personal);
        Assert.Contains("30 anos", personal);
        Assert.Contains("mediana", personal);
        Assert.Contains("no máximo 3 frases", personal);
        Assert.Contains("\"max_tokens\":220", f.DeepSeekCalls[0]);
        Assert.Contains("Perfil: EMPRESA (MEI)", business);
        Assert.Contains("teto do MEI", business);
    }
}
