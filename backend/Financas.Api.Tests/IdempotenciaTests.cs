using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

/// <summary>RN-45: o mesmo POST com a mesma Idempotency-Key não cria dois lançamentos.</summary>
public class IdempotenciaTests
{
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name);
    private record IdBody(Guid Id);
    private record Tx(Guid Id, string Description);

    private static async Task<(HttpClient c, object body)> SetupAsync(ApiFactory f, string email = "user@teste.com")
    {
        var c = await f.CreateUserClientAsync(email);
        var cat = (await c.GetFromJsonAsync<List<Category>>("/api/categories"))!.First(x => x.Type == "Expense");
        var acc = (await c.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        return (c, new { accountId = acc.Id, categoryId = cat.Id, description = "Almoço", amount = 45m, type = "Expense", date = "2026-10-10" });
    }

    private static Task<HttpResponseMessage> PostAsync(HttpClient c, object body, string? key)
    {
        var req = new HttpRequestMessage(HttpMethod.Post, "/api/transactions") { Content = JsonContent.Create(body) };
        if (key is not null) req.Headers.Add("Idempotency-Key", key);
        return c.SendAsync(req);
    }

    private static async Task<int> CountAsync(HttpClient c) =>
        (await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-10"))!.Count;

    [Fact]
    public async Task Mesma_chave_devolve_o_mesmo_lancamento_mesmo_em_paralelo()
    {
        using var f = new ApiFactory();
        var (c, body) = await SetupAsync(f);

        var first = await PostAsync(c, body, "wa:call_abc");
        var again = await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => PostAsync(c, body, "wa:call_abc")));

        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        var id = (await first.Content.ReadFromJsonAsync<IdBody>())!.Id;
        foreach (var r in again)
        {
            Assert.Equal(HttpStatusCode.OK, r.StatusCode);
            Assert.Equal(id, (await r.Content.ReadFromJsonAsync<IdBody>())!.Id);
        }
        Assert.Equal(1, await CountAsync(c));
    }

    [Fact]
    public async Task Sem_chave_ou_com_chave_diferente_cria_normalmente()
    {
        using var f = new ApiFactory();
        var (c, body) = await SetupAsync(f);

        await PostAsync(c, body, null);
        await PostAsync(c, body, null);   // o app sem chave continua podendo lançar duas vezes de propósito
        await PostAsync(c, body, "wa:call_1");
        await PostAsync(c, body, "wa:call_2");

        Assert.Equal(4, await CountAsync(c));
    }

    [Fact]
    public async Task Chave_vale_por_usuario()
    {
        using var f = new ApiFactory();
        var (ana, bodyAna) = await SetupAsync(f, "ana@teste.com");
        var (bia, bodyBia) = await SetupAsync(f, "bia@teste.com");

        Assert.Equal(HttpStatusCode.Created, (await PostAsync(ana, bodyAna, "wa:call_x")).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await PostAsync(bia, bodyBia, "wa:call_x")).StatusCode);
    }

    [Fact]
    public async Task Chave_longa_demais_e_recusada()
    {
        using var f = new ApiFactory();
        var (c, body) = await SetupAsync(f);
        Assert.Equal(HttpStatusCode.BadRequest, (await PostAsync(c, body, new string('k', 101))).StatusCode);
    }
}
