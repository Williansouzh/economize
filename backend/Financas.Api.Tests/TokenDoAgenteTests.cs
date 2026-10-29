using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

// ---------- O token do agente do WhatsApp é curto e só vale nas rotas que o assistente usa ----------
public class TokenDoAgenteTests
{
    private record Auth(string Token);
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name);
    private record Created(Guid Id);

    /// <summary>Vincula um número e devolve um cliente com o token que o agente recebe para ele.</summary>
    private static async Task<(HttpClient Agent, string Token)> AgentAsUserAsync(ApiFactory factory, HttpClient user)
    {
        const string phone = "5511955550000";
        var code = (await (await user.PostAsync("/api/me/whatsapp-code", null)).Content
            .ReadFromJsonAsync<Dictionary<string, object>>())!["code"].ToString();
        var agent = factory.CreateAgentClient();
        Assert.Equal(HttpStatusCode.OK, (await agent.PostAsJsonAsync("/api/agent/link", new { phone, code })).StatusCode);
        var token = (await (await agent.PostAsJsonAsync("/api/agent/token", new { phone })).Content.ReadFromJsonAsync<Auth>())!.Token;

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return (client, token);
    }

    [Fact]
    public async Task Vale_15_minutos_em_vez_de_14_dias()
    {
        using var factory = new ApiFactory();
        var user = await factory.CreateUserClientAsync();
        var (_, token) = await AgentAsUserAsync(factory, user);

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.InRange(jwt.ValidTo - DateTime.UtcNow, TimeSpan.FromMinutes(14), TimeSpan.FromMinutes(15.1));
    }

    [Fact]
    public async Task Funciona_nas_rotas_do_assistente()
    {
        using var factory = new ApiFactory();
        var user = await factory.CreateUserClientAsync();
        var (agent, _) = await AgentAsUserAsync(factory, user);

        var categories = (await agent.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var account = (await agent.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        Assert.Equal(HttpStatusCode.OK, (await agent.GetAsync("/api/profiles")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await agent.GetAsync("/api/dashboard?month=2026-10")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await agent.PostAsync("/api/insights/quota/whatsapp", null)).StatusCode);

        var created = await agent.PostAsJsonAsync("/api/transactions", new
        {
            accountId = account.Id, categoryId = categories.First(c => c.Type == "Expense").Id,
            amount = 30m, type = "Expense", date = "2026-10-17", description = "almoço", isPaid = true,
        });
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var id = (await created.Content.ReadFromJsonAsync<Created>())!.Id;
        Assert.Equal(HttpStatusCode.OK, (await agent.GetAsync("/api/transactions?month=2026-10")).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await agent.DeleteAsync($"/api/transactions/{id}")).StatusCode);
    }

    [Theory]
    [InlineData("DELETE", "/api/me")]               // excluir a conta
    [InlineData("POST", "/api/me/reset")]           // começar do zero
    [InlineData("DELETE", "/api/me/sessions")]      // derrubar as sessões
    [InlineData("DELETE", "/api/me/whatsapp")]      // desvincular o número
    [InlineData("POST", "/api/me/token")]           // trocar por um token de 14 dias
    [InlineData("GET", "/api/me")]
    [InlineData("GET", "/api/export/transactions.csv")]
    [InlineData("POST", "/api/profiles")]
    [InlineData("POST", "/api/import/commit")]
    [InlineData("POST", "/api/budgets")]
    [InlineData("PUT", "/api/accounts/00000000-0000-0000-0000-000000000000")]
    [InlineData("GET", "/api/admin/stats")]
    public async Task E_recusado_nas_outras_rotas(string method, string path)
    {
        using var factory = new ApiFactory();
        var user = await factory.CreateUserClientAsync();
        var (agent, _) = await AgentAsUserAsync(factory, user);

        var res = await agent.SendAsync(new HttpRequestMessage(new HttpMethod(method), path)
        {
            Content = method is "GET" or "DELETE" ? null : JsonContent.Create(new { }),
        });

        Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);
        // O token normal do app continua podendo tudo.
        Assert.Equal(HttpStatusCode.OK, (await user.GetAsync("/api/me")).StatusCode);
    }
}
