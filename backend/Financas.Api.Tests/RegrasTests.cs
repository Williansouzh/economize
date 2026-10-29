using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

public class RegrasTests
{
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name);
    private record ErrorBody(string Error);

    private static async Task<(List<Category> cats, Account acc)> LoadAsync(HttpClient client)
    {
        var cats = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var acc = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        return (cats, acc);
    }

    private static object Tx(Account acc, Category cat, string type) => new
    {
        accountId = acc.Id, categoryId = cat.Id, description = "teste", amount = 10m,
        type, date = "2026-10-10", isPaid = true,
    };

    // ---------- RN-09: tipo da categoria ----------

    [Fact]
    public async Task Despesa_com_categoria_de_receita_e_recusada()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var (cats, acc) = await LoadAsync(client);
        var salario = cats.Single(c => c.Name == "Salário");

        var res = await client.PostAsJsonAsync("/api/transactions", Tx(acc, salario, "Expense"));

        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
        Assert.Equal("Escolha uma categoria de despesa.", (await res.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
    }

    [Fact]
    public async Task Receita_com_categoria_de_despesa_e_recusada_tambem_na_edicao()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var (cats, acc) = await LoadAsync(client);
        var salario = cats.Single(c => c.Name == "Salário");
        var mercado = cats.Single(c => c.Name == "Alimentação");

        var created = await client.PostAsJsonAsync("/api/transactions", Tx(acc, salario, "Income"));
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var id = (await created.Content.ReadFromJsonAsync<Dictionary<string, Guid>>())!["id"];

        var edit = await client.PutAsJsonAsync($"/api/transactions/{id}", Tx(acc, mercado, "Income"));
        Assert.Equal(HttpStatusCode.BadRequest, edit.StatusCode);
        Assert.Equal("Escolha uma categoria de receita.", (await edit.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
    }

    [Fact]
    public async Task Orcamento_so_aceita_categoria_de_despesa()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var (cats, _) = await LoadAsync(client);

        var receita = await client.PostAsJsonAsync("/api/budgets",
            new { categoryId = cats.Single(c => c.Name == "Salário").Id, month = "2026-10", limit = 100m });
        var despesa = await client.PostAsJsonAsync("/api/budgets",
            new { categoryId = cats.Single(c => c.Name == "Lazer").Id, month = "2026-10", limit = 100m });

        Assert.Equal(HttpStatusCode.BadRequest, receita.StatusCode);
        Assert.Equal(HttpStatusCode.OK, despesa.StatusCode);
    }

    // ---------- RN-24: limite de tentativas na vinculação ----------

    private static async Task<string> NewCodeAsync(HttpClient user)
    {
        var res = await user.PostAsync("/api/me/whatsapp-code", null);
        return (await res.Content.ReadFromJsonAsync<Dictionary<string, object>>())!["code"].ToString()!;
    }

    private static Task<HttpResponseMessage> LinkAsync(HttpClient agent, string phone, string code) =>
        agent.PostAsJsonAsync("/api/agent/link", new { phone, code });

    [Fact]
    public async Task Numero_e_bloqueado_apos_5_codigos_errados_mesmo_acertando_depois()
    {
        using var factory = new ApiFactory();
        var user = await factory.CreateUserClientAsync();
        var agent = factory.CreateAgentClient();
        var code = await NewCodeAsync(user);
        var wrong = code == "111111" ? "222222" : "111111";

        for (var i = 0; i < 5; i++)
            Assert.Equal(HttpStatusCode.BadRequest, (await LinkAsync(agent, "5511900000001", wrong)).StatusCode);

        var blocked = await LinkAsync(agent, "5511900000001", code);
        Assert.Equal(HttpStatusCode.TooManyRequests, blocked.StatusCode);
        Assert.StartsWith("Muitas tentativas", (await blocked.Content.ReadFromJsonAsync<ErrorBody>())!.Error);

        // Outro número não é afetado e o código continua válido para ele.
        Assert.Equal(HttpStatusCode.OK, (await LinkAsync(agent, "5511900000002", code)).StatusCode);
    }

    [Fact]
    public async Task Acerto_zera_o_contador_de_falhas()
    {
        using var factory = new ApiFactory();
        var user = await factory.CreateUserClientAsync();
        var agent = factory.CreateAgentClient();
        const string phone = "5511900000003";

        for (var i = 0; i < 4; i++) await LinkAsync(agent, phone, "000000");
        Assert.Equal(HttpStatusCode.OK, (await LinkAsync(agent, phone, await NewCodeAsync(user))).StatusCode);

        // Depois do acerto, mais 4 erros ainda não bloqueiam.
        for (var i = 0; i < 4; i++) await LinkAsync(agent, phone, "000000");
        Assert.Equal(HttpStatusCode.OK, (await LinkAsync(agent, phone, await NewCodeAsync(user))).StatusCode);
    }

    [Fact]
    public async Task Varios_numeros_errando_somam_no_teto_geral()
    {
        // Quem tenta adivinhar o código de muitos números diferentes não ganha 5 tentativas por número.
        using var factory = new ApiFactory { Settings = { ["Agent:LinkGlobalMaxFailures"] = "3" } };
        var user = await factory.CreateUserClientAsync();
        var agent = factory.CreateAgentClient();
        var code = await NewCodeAsync(user);
        var wrong = code == "111111" ? "222222" : "111111";

        for (var i = 0; i < 3; i++)
            Assert.Equal(HttpStatusCode.BadRequest, (await LinkAsync(agent, $"551190000010{i}", wrong)).StatusCode);

        // Um número que nunca errou também fica bloqueado, mesmo com o código certo.
        Assert.Equal(HttpStatusCode.TooManyRequests, (await LinkAsync(agent, "5511900000199", code)).StatusCode);
    }

    [Theory]
    [InlineData("*")]
    [InlineData("+55 11 9999")]
    [InlineData("")]
    public async Task Numero_que_nao_e_so_digitos_e_recusado(string phone)
    {
        using var factory = new ApiFactory();
        var user = await factory.CreateUserClientAsync();
        var res = await LinkAsync(factory.CreateAgentClient(), phone, await NewCodeAsync(user));
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    // ---------- Ícone da conta ----------

    private record AccountWithIcon(Guid Id, string Name, string Icon);

    [Fact]
    public async Task Conta_guarda_icone_e_carteira_padrao_ja_vem_com_icone()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        var res = await client.PostAsJsonAsync("/api/accounts",
            new { name = "Nubank", initialBalance = 0m, color = "#8A05BE", icon = "credit_card" });
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);

        var accounts = (await client.GetFromJsonAsync<List<AccountWithIcon>>("/api/accounts"))!;
        Assert.Equal("credit_card", accounts.Single(a => a.Name == "Nubank").Icon);
        Assert.Equal("account_balance_wallet", accounts.Single(a => a.Name == "Carteira").Icon);
    }

    // ---------- Chave JWT ----------

    [Fact]
    public void Producao_nao_sobe_com_chave_de_desenvolvimento()
    {
        using var factory = new ApiFactory { Environment = "Production", JwtKey = Services.JwtKeyGuard.DevelopmentKey };
        var ex = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());
        Assert.Contains("desenvolvimento", ex.Message);
    }

    [Theory]
    [InlineData("")]
    [InlineData("curta-demais")]
    public void Producao_nao_sobe_sem_chave_ou_com_chave_curta(string key)
    {
        using var factory = new ApiFactory { Environment = "Production", JwtKey = key };
        var ex = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());
        Assert.Contains("Jwt:Key", ex.Message);
    }

    [Fact]
    public async Task Producao_sobe_com_chave_propria()
    {
        using var factory = new ApiFactory { Environment = "Production", JwtKey = new string('x', 48) };
        var client = await factory.CreateUserClientAsync();
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/me")).StatusCode);
    }
}
