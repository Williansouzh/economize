using System.Net;
using System.Net.Http.Json;
using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Financas.Api.Tests;

// ---------- RN-30: exclusão da conta ----------
public class ExclusaoDeContaTests
{
    private record Category(Guid Id, string Name);
    private record Account(Guid Id, string Name);
    private record LinkCode(string Code);
    private record ErrorBody(string Error);

    private static HttpRequestMessage Delete(string password) =>
        new(HttpMethod.Delete, "/api/me") { Content = JsonContent.Create(new { password }) };

    private static ApiFactory FactoryWithAgent() => new() { Settings = { ["Agent:Url"] = "http://agente" } };

    [Fact]
    public async Task Excluir_conta_apaga_todos_os_dados_e_avisa_o_agente_mas_nao_toca_em_outros_usuarios()
    {
        using var factory = FactoryWithAgent();
        var client = await factory.CreateUserClientAsync("sai@teste.com");
        var other = await factory.CreateUserClientAsync("fica@teste.com");

        // Dados de todos os tipos: lançamento, transferência, orçamento e WhatsApp vinculado.
        var cats = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var comida = cats.Single(c => c.Name == "Alimentação");
        await client.PostAsJsonAsync("/api/accounts", new { name = "Nubank", initialBalance = 0m });
        var accs = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!;
        await client.PostAsJsonAsync("/api/transactions", new
        {
            accountId = accs[0].Id, categoryId = comida.Id, description = "almoço", amount = 30m, type = "Expense", date = "2026-10-10",
        });
        await client.PostAsJsonAsync("/api/transfers", new { fromAccountId = accs[0].Id, toAccountId = accs[1].Id, amount = 5m, date = "2026-10-10" });
        await client.PostAsJsonAsync("/api/budgets", new { categoryId = comida.Id, month = "2026-10", limit = 100m, recurring = true });
        var code = await (await client.PostAsync("/api/me/whatsapp-code", null)).Content.ReadFromJsonAsync<LinkCode>();
        Assert.Equal(HttpStatusCode.OK,
            (await factory.CreateAgentClient().PostAsJsonAsync("/api/agent/link", new { phone = "5511999990000", code = code!.Code })).StatusCode);

        var res = await client.SendAsync(Delete(ApiFactory.Password));

        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            Assert.Equal(1, await db.Users.CountAsync());
            Assert.Equal(1, await db.Accounts.CountAsync());
            Assert.Equal(13, await db.Categories.CountAsync());
            Assert.Equal(0, await db.Transactions.CountAsync());
            Assert.Equal(0, await db.Transfers.CountAsync());
            Assert.Equal(0, await db.Budgets.CountAsync());
        }
        Assert.Contains(factory.AgentCalls, c => c.StartsWith("/internal/forget") && c.Contains("5511999990000"));
        Assert.Equal(HttpStatusCode.OK, (await other.GetAsync("/api/dashboard")).StatusCode);

        // A conta deixa de existir: login falha e o e-mail pode ser usado de novo.
        var login = await factory.CreateClient().PostAsJsonAsync("/api/auth/login", new { email = "sai@teste.com", password = ApiFactory.Password });
        Assert.Equal(HttpStatusCode.Unauthorized, login.StatusCode);
        await factory.CreateUserClientAsync("sai@teste.com");
    }

    [Fact]
    public async Task Excluir_conta_exige_a_senha()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        var res = await client.SendAsync(Delete("senha-errada"));

        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
        Assert.Equal("Senha incorreta.", (await res.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/me")).StatusCode);
    }

    private static HttpRequestMessage Reset(string password) =>
        new(HttpMethod.Post, "/api/me/reset") { Content = JsonContent.Create(new { password }) };

    [Fact]
    public async Task Comecar_do_zero_apaga_os_dados_mas_mantem_o_cadastro_e_o_whatsapp()
    {
        using var factory = FactoryWithAgent();
        var client = await factory.CreateUserClientAsync("zera@teste.com");
        var other = await factory.CreateUserClientAsync("fica@teste.com");

        var cats = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var comida = cats.Single(c => c.Name == "Alimentação");
        await client.PostAsJsonAsync("/api/categories", new { name = "Pet", type = "Expense", icon = "pets", color = "#000000" });
        await client.PostAsJsonAsync("/api/accounts", new { name = "Nubank", initialBalance = 500m });
        var accs = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!;
        await client.PostAsJsonAsync("/api/transactions", new
        {
            accountId = accs[0].Id, categoryId = comida.Id, description = "almoço", amount = 30m, type = "Expense", date = "2026-10-10",
        });
        await client.PostAsJsonAsync("/api/transfers", new { fromAccountId = accs[0].Id, toAccountId = accs[1].Id, amount = 5m, date = "2026-10-10" });
        await client.PostAsJsonAsync("/api/budgets", new { categoryId = comida.Id, month = "2026-10", limit = 100m, recurring = true });
        await client.PostAsJsonAsync("/api/goals", new { name = "Viagem", target = 1000m });
        var code = await (await client.PostAsync("/api/me/whatsapp-code", null)).Content.ReadFromJsonAsync<LinkCode>();
        await factory.CreateAgentClient().PostAsJsonAsync("/api/agent/link", new { phone = "5511977770000", code = code!.Code });
        await other.PostAsJsonAsync("/api/goals", new { name = "Carro", target = 1000m });

        Assert.Equal(HttpStatusCode.BadRequest, (await client.SendAsync(Reset("senha-errada"))).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(Reset(ApiFactory.Password))).StatusCode);

        // Volta como no cadastro: só a Carteira e as 13 categorias padrão.
        var newAccs = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!;
        Assert.Equal("Carteira", Assert.Single(newAccs).Name);
        Assert.Equal(13, (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!.Count);
        using (var scope = factory.Services.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var me = await db.Users.SingleAsync(u => u.Email == "zera@teste.com");
            Assert.Equal("5511977770000", me.WhatsAppPhone);
            Assert.Equal(0, await db.Transactions.CountAsync());
            Assert.Equal(0, await db.Transfers.CountAsync());
            Assert.Equal(0, await db.Budgets.CountAsync());
            Assert.Equal(0, await db.Goals.CountAsync(g => g.UserId == me.Id));
            Assert.Equal(1, await db.Goals.CountAsync());
        }
        // O histórico da conversa vai junto; a sessão continua valendo.
        Assert.Contains(factory.AgentCalls, c => c.StartsWith("/internal/forget") && c.Contains("5511977770000"));
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/dashboard")).StatusCode);
    }

    [Fact]
    public async Task Desconectar_o_whatsapp_pede_ao_agente_para_apagar_o_historico()
    {
        using var factory = FactoryWithAgent();
        var client = await factory.CreateUserClientAsync();
        var code = await (await client.PostAsync("/api/me/whatsapp-code", null)).Content.ReadFromJsonAsync<LinkCode>();
        await factory.CreateAgentClient().PostAsJsonAsync("/api/agent/link", new { phone = "5511888880000", code = code!.Code });

        await client.DeleteAsync("/api/me/whatsapp");

        Assert.Contains(factory.AgentCalls, c => c.Contains("5511888880000"));
    }
}
