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
}
