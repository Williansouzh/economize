using System.Net;
using System.Net.Http.Json;
using Financas.Api.Data;
using Financas.Api.Endpoints;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Financas.Api.Tests;

// ---------- Condições de corrida: pedidos iguais ao mesmo tempo só têm efeito uma vez ----------
public class CorridasTests
{
    /// <summary>Dispara as requisições juntas, sem esperar uma terminar para mandar a outra.</summary>
    private static Task<HttpResponseMessage[]> AllAtOnce(int count, Func<int, Task<HttpResponseMessage>> send) =>
        Task.WhenAll(Enumerable.Range(0, count).Select(i => Task.Run(() => send(i))));

    // ---------- Recuperação de senha ----------

    /// <summary>Sem o limite de 10 por minuto por IP: simula um ataque vindo de muitos IPs.</summary>
    private static ApiFactory ManyIps() => new() { Settings = { ["RateLimit:AuthPerMinute"] = "1000" } };

    private static async Task<(HttpClient Anon, string Code)> ResetCodeAsync(ApiFactory factory)
    {
        await factory.CreateUserClientAsync("ana@teste.com");
        var anon = factory.CreateClient();
        await anon.PostAsJsonAsync("/api/auth/forgot-password", new { email = "ana@teste.com" });
        return (anon, factory.Emails[^1].Subject[^6..]);
    }

    [Fact]
    public async Task Chutes_ao_mesmo_tempo_nao_furam_o_limite_de_5_tentativas()
    {
        // Antes: cada pedido lia "0 erros", conferia o código e gravava "1". Com chutes em paralelo,
        // bem mais de 5 eram conferidos. Aqui, com 4 erros já feitos, sobra 1 tentativa: dos 30 pedidos
        // juntos (todos com o código certo), no máximo 1 pode chegar a conferir o código.
        using var factory = ManyIps();
        var (anon, code) = await ResetCodeAsync(factory);
        var wrong = code == "111111" ? "222222" : "111111";
        for (var i = 0; i < 4; i++)
            await anon.PostAsJsonAsync("/api/auth/reset-password", new { email = "ana@teste.com", code = wrong, newPassword = "nova-senha-123" });

        // Um chute errado e 29 com o código certo, todos juntos: a única tentativa que sobra pode ser de qualquer um.
        var res = await AllAtOnce(30, i => anon.PostAsJsonAsync("/api/auth/reset-password",
            new { email = "ana@teste.com", code = i == 0 ? wrong : code, newPassword = $"senha-nova-{i:00}" }));

        Assert.True(res.Count(r => r.StatusCode == HttpStatusCode.OK) <= 1);
        using var scope = factory.Services.CreateScope();
        var user = await scope.ServiceProvider.GetRequiredService<AppDbContext>().Users.SingleAsync();
        // Ou o código foi gasto por 1 acerto (contador zerado), ou o erro gastou a última tentativa (5).
        Assert.True(user.ResetCodeHash is null || user.ResetAttempts == 5);
    }

    [Fact]
    public async Task Codigo_certo_enviado_duas_vezes_ao_mesmo_tempo_troca_a_senha_uma_vez()
    {
        using var factory = ManyIps();
        var (anon, code) = await ResetCodeAsync(factory);
        string[] senhas = ["primeira-123", "segunda-123"];

        var res = await AllAtOnce(2, i => anon.PostAsJsonAsync("/api/auth/reset-password",
            new { email = "ana@teste.com", code, newPassword = senhas[i] }));

        Assert.Single(res, r => r.StatusCode == HttpStatusCode.OK);
        Assert.Single(res, r => r.StatusCode == HttpStatusCode.BadRequest);
        // Vale a senha de quem recebeu 200, e só ela.
        var vencedora = senhas[Array.FindIndex(res, r => r.StatusCode == HttpStatusCode.OK)];
        foreach (var senha in senhas)
        {
            var login = await anon.PostAsJsonAsync("/api/auth/login", new { email = "ana@teste.com", password = senha });
            Assert.Equal(senha == vencedora ? HttpStatusCode.OK : HttpStatusCode.Unauthorized, login.StatusCode);
        }
    }

    // ---------- Índices únicos (migration SemDuplicados) ----------

    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name);
    private record Imported(int Created);

    [Fact]
    public async Task Duas_categorias_com_o_mesmo_nome_ao_mesmo_tempo_criam_uma()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        // Maiúsculas diferentes também contam como o mesmo nome.
        string[] nomes = ["Pets", "PETS"];
        var res = await AllAtOnce(2, i => client.PostAsJsonAsync("/api/categories", new { name = nomes[i], type = "Expense" }));

        Assert.Single(res, r => r.StatusCode == HttpStatusCode.Created);
        Assert.Single(res, r => r.StatusCode == HttpStatusCode.Conflict);
        var all = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        Assert.Single(all, c => c.Name.Equals("pets", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task Renomear_para_um_nome_que_outra_categoria_acabou_de_ganhar_da_409()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var ids = new List<Guid>();
        foreach (var n in new[] { "Cachorro", "Gato" })
            ids.Add((await (await client.PostAsJsonAsync("/api/categories", new { name = n, type = "Expense" })).Content.ReadFromJsonAsync<Category>())!.Id);

        var res = await AllAtOnce(2, i => client.PutAsJsonAsync($"/api/categories/{ids[i]}", new { name = "Pets", type = "Expense" }));

        Assert.Single(res, r => r.StatusCode == HttpStatusCode.OK);
        Assert.Single(res, r => r.StatusCode == HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task O_mesmo_extrato_confirmado_duas_vezes_ao_mesmo_tempo_entra_uma_vez()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var account = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        var food = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!.First(c => c.Type == "Expense");
        var items = Enumerable.Range(1, 30).Select(i => new
        {
            date = "2026-10-10", description = $"Compra {i}", amount = 10m + i, type = "Expense", categoryId = food.Id, externalId = $"b:FIT{i}",
        }).ToList();

        var res = await AllAtOnce(2, _ => client.PostAsJsonAsync("/api/import/commit", new { accountId = account.Id, items }));

        Assert.All(res, r => Assert.Equal(HttpStatusCode.OK, r.StatusCode));
        var created = await Task.WhenAll(res.Select(async r => (await r.Content.ReadFromJsonAsync<Imported>())!.Created));
        Assert.Equal(30, created.Sum()); // a segunda vê que já entraram (ou entra só o que faltava)
        using var scope = factory.Services.CreateScope();
        Assert.Equal(30, await scope.ServiceProvider.GetRequiredService<AppDbContext>().Transactions.CountAsync(t => t.ExternalId != null));
    }

    [Fact]
    public async Task Codigo_de_vinculacao_repetido_e_sorteado_de_novo()
    {
        using var factory = new ApiFactory();
        var ana = await factory.CreateUserClientAsync("ana@teste.com");
        await factory.CreateUserClientAsync("bia@teste.com");
        var anaCode = (await (await ana.PostAsync("/api/me/whatsapp-code", null)).Content.ReadFromJsonAsync<Dictionary<string, object>>())!["code"].ToString()!;

        // O sorteio da Bia cai primeiro no código ativo da Ana.
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var bia = await db.Users.SingleAsync(u => u.Email == "bia@teste.com");
        var sorteios = new Queue<string>([anaCode, "123456"]);
        await WhatsAppEndpoints.IssueLinkCodeAsync(db, bia, sorteios.Dequeue);

        Assert.Equal("123456", bia.WhatsAppLinkCode);
        Assert.Equal(1, await db.Users.CountAsync(u => u.WhatsAppLinkCode == anaCode));
    }

    // ---------- Operações atômicas e locks (sem migration) ----------

    private record Goal(Guid Id, decimal Saved);
    private record Me(string? WhatsAppPhone);

    [Fact]
    public async Task O_mesmo_codigo_de_vinculacao_de_dois_numeros_vincula_so_um()
    {
        using var factory = new ApiFactory();
        var user = await factory.CreateUserClientAsync();
        var code = (await (await user.PostAsync("/api/me/whatsapp-code", null)).Content.ReadFromJsonAsync<Dictionary<string, object>>())!["code"].ToString();
        var agent = factory.CreateAgentClient();
        string[] phones = ["5511900000301", "5511900000302"];

        var res = await AllAtOnce(2, i => agent.PostAsJsonAsync("/api/agent/link", new { phone = phones[i], code }));

        Assert.Single(res, r => r.StatusCode == HttpStatusCode.OK);
        Assert.Single(res, r => r.StatusCode == HttpStatusCode.BadRequest);
        // Fica vinculado o número que recebeu "vinculado", e não o outro.
        var linked = (await user.GetFromJsonAsync<Me>("/api/me"))!.WhatsAppPhone;
        Assert.Equal(phones[Array.FindIndex(res, r => r.StatusCode == HttpStatusCode.OK)], linked);
    }

    [Fact]
    public async Task Depositos_ao_mesmo_tempo_na_meta_entram_todos()
    {
        // Antes: os dois liam o mesmo valor guardado e um depósito se perdia.
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var goal = (await (await client.PostAsJsonAsync("/api/goals", new { name = "Viagem", target = 10_000m })).Content.ReadFromJsonAsync<Goal>())!;

        await AllAtOnce(10, _ => client.PostAsJsonAsync($"/api/goals/{goal.Id}/deposit", new { amount = 100m }));
        // Retirar mais do que tem continua parando no zero.
        await client.PostAsJsonAsync($"/api/goals/{goal.Id}/deposit", new { amount = -50m });

        var saved = (await client.GetFromJsonAsync<List<Goal>>("/api/goals"))!.Single().Saved;
        Assert.Equal(950m, saved);
    }

    [Fact]
    public async Task Pedidos_juntos_de_perfil_de_empresa_nao_passam_do_limite_de_2()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        await client.PostAsJsonAsync("/api/profiles", new { name = "Primeira", isMei = true });

        var res = await AllAtOnce(3, i => client.PostAsJsonAsync("/api/profiles", new { name = $"Empresa {i}", isMei = false }));

        Assert.Single(res, r => r.StatusCode == HttpStatusCode.Created);
        Assert.Equal(2, res.Count(r => r.StatusCode == HttpStatusCode.BadRequest));
        using var scope = factory.Services.CreateScope();
        Assert.Equal(2, await scope.ServiceProvider.GetRequiredService<AppDbContext>().Profiles.CountAsync());
    }

    [Fact]
    public async Task Comecar_do_zero_duas_vezes_ao_mesmo_tempo_deixa_uma_carteira()
    {
        // Antes: o segundo apagava antes de o primeiro gravar o padrão, e a conta ficava com tudo em dobro.
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        var res = await AllAtOnce(2, _ => client.SendAsync(new HttpRequestMessage(HttpMethod.Post, "/api/me/reset")
            { Content = JsonContent.Create(new { password = ApiFactory.Password }) }));

        Assert.All(res, r => Assert.Equal(HttpStatusCode.NoContent, r.StatusCode));
        Assert.Equal("Carteira", Assert.Single((await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!).Name);
        Assert.Equal(13, (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!.Count);
    }

    [Fact]
    public async Task Duas_analises_da_ia_ao_mesmo_tempo_nao_dao_erro()
    {
        // Antes: a segunda quebrava ao gravar no cache (500) e não devolvia a cota.
        using var factory = new ApiFactory { DeepSeekReply = """{"summary":"ok","alerts":[],"tips":[],"potentialSavings":0,"healthScore":50}""" };
        var client = await factory.CreateUserClientAsync();

        var res = await AllAtOnce(2, _ => client.PostAsJsonAsync("/api/insights", new { month = "2026-10" }));

        Assert.All(res, r => Assert.Equal(HttpStatusCode.OK, r.StatusCode));
        using var scope = factory.Services.CreateScope();
        Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<AppDbContext>().AiCache.CountAsync());
    }

    [Fact]
    public async Task Salvar_o_mesmo_orcamento_ao_mesmo_tempo_grava_um()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var food = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!.First(c => c.Type == "Expense");
        decimal[] limits = [300m, 500m];

        var res = await AllAtOnce(2, i => client.PostAsJsonAsync("/api/budgets", new { categoryId = food.Id, month = "2026-10", limit = limits[i] }));

        Assert.All(res, r => Assert.Equal(HttpStatusCode.OK, r.StatusCode)); // antes: um deles recebia 500
        using var scope = factory.Services.CreateScope();
        var budget = await scope.ServiceProvider.GetRequiredService<AppDbContext>().Budgets.SingleAsync();
        Assert.Contains(budget.Limit, limits);
    }

    [Fact]
    public async Task Dois_cadastros_com_o_mesmo_email_ao_mesmo_tempo_criam_uma_conta()
    {
        using var factory = new ApiFactory { Settings = { ["RateLimit:AuthPerMinute"] = "1000" } };
        var anon = factory.CreateClient();

        var res = await AllAtOnce(2, _ => anon.PostAsJsonAsync("/api/auth/register",
            new { name = "Ana", email = "ana@teste.com", password = "senha12345" }));

        Assert.Single(res, r => r.StatusCode == HttpStatusCode.OK);
        Assert.Single(res, r => r.StatusCode == HttpStatusCode.Conflict); // antes: 500
        using var scope = factory.Services.CreateScope();
        Assert.Equal(1, await scope.ServiceProvider.GetRequiredService<AppDbContext>().Users.CountAsync());
    }

    [Fact]
    public async Task Apagar_categoria_enquanto_um_lancamento_e_criado_nela_nunca_da_500()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var account = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        var cat = (await (await client.PostAsJsonAsync("/api/categories", new { name = "Pets", type = "Expense" })).Content.ReadFromJsonAsync<Category>())!;

        var res = await AllAtOnce(2, i => i == 0
            ? client.DeleteAsync($"/api/categories/{cat.Id}")
            : client.PostAsJsonAsync("/api/transactions", new
            {
                accountId = account.Id, categoryId = cat.Id, amount = 10m, type = "Expense", date = "2026-10-10", isPaid = true,
            }));

        Assert.DoesNotContain(res, r => r.StatusCode == HttpStatusCode.InternalServerError);
        // Ou a categoria foi apagada e o lançamento recusado, ou o lançamento entrou e a exclusão foi recusada.
        var deleted = res[0].StatusCode == HttpStatusCode.NoContent;
        Assert.Equal(deleted ? HttpStatusCode.BadRequest : HttpStatusCode.Created, res[1].StatusCode);
        if (!deleted) Assert.Equal(HttpStatusCode.Conflict, res[0].StatusCode);
    }
}

