using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

/// <summary>Duas instâncias da API apontando para o mesmo PostgreSQL, como réplicas atrás de um balanceador.</summary>
public class ReplicasTests
{

    [Fact]
    public async Task Duas_replicas_sobem_juntas_e_compartilham_dados_e_limite_de_vinculacao()
    {
        var db = $"financas_test_{Guid.NewGuid():N}";
        using var a = new ApiFactory { DatabaseName = db };
        using var b = new ApiFactory { DatabaseName = db, OwnsDatabase = false };

        // Sobem ao mesmo tempo: as duas tentam aplicar as migrations, e o lock do EF Core serializa.
        await Task.WhenAll(Task.Run(() => a.CreateClient()), Task.Run(() => b.CreateClient()));

        // Usuário criado na réplica A faz login pela B.
        await a.CreateUserClientAsync("replica@teste.com");
        var login = await b.CreateClient().PostAsJsonAsync("/api/auth/login", new { email = "replica@teste.com", password = "123456" });
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);

        // Falhas de vinculação somam entre réplicas: 3 na A + 2 na B = bloqueado nas duas.
        const string phone = "5511900000099";
        var agentA = a.CreateAgentClient();
        var agentB = b.CreateAgentClient();
        for (var i = 0; i < 3; i++) await agentA.PostAsJsonAsync("/api/agent/link", new { phone, code = "000000" });
        for (var i = 0; i < 2; i++) await agentB.PostAsJsonAsync("/api/agent/link", new { phone, code = "000000" });

        Assert.Equal(HttpStatusCode.TooManyRequests,
            (await agentA.PostAsJsonAsync("/api/agent/link", new { phone, code = "000000" })).StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests,
            (await agentB.PostAsJsonAsync("/api/agent/link", new { phone, code = "000000" })).StatusCode);
    }

    [Fact]
    public async Task Falhas_simultaneas_nao_se_perdem()
    {
        using var factory = new ApiFactory();
        var agent = factory.CreateAgentClient();
        const string phone = "5511900000098";

        // 5 tentativas em paralelo: o incremento atômico no banco conta todas.
        await Task.WhenAll(Enumerable.Range(0, 5).Select(_ =>
            agent.PostAsJsonAsync("/api/agent/link", new { phone, code = "000000" })));

        Assert.Equal(HttpStatusCode.TooManyRequests,
            (await agent.PostAsJsonAsync("/api/agent/link", new { phone, code = "000000" })).StatusCode);
    }

    [Fact]
    public async Task Descricao_longa_e_recusada_antes_de_chegar_no_banco()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var cats = (await client.GetFromJsonAsync<List<Dictionary<string, object>>>("/api/categories"))!;
        var acc = (await client.GetFromJsonAsync<List<Dictionary<string, object>>>("/api/accounts"))![0];
        var cat = cats.First(c => c["type"].ToString() == "Expense");

        var res = await client.PostAsJsonAsync("/api/transactions", new
        {
            accountId = acc["id"].ToString(), categoryId = cat["id"].ToString(),
            description = new string('x', 201), amount = 10m, type = "Expense", date = "2026-10-10",
        });

        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    [Fact]
    public async Task Health_responde_com_o_banco_no_ar()
    {
        using var factory = new ApiFactory();
        Assert.Equal(HttpStatusCode.OK, (await factory.CreateClient().GetAsync("/health")).StatusCode);
    }
}
