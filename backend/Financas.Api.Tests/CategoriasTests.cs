using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

// ---------- RN-13 e RN-31: categorias do usuário ----------
public class CategoriasTests
{
    private record Category(Guid Id, string Name, string Type, string Icon, string Color);
    private record Account(Guid Id, string Name);
    private record ErrorBody(string Error);

    [Fact]
    public async Task Cria_edita_e_exclui_categoria_propria()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        var res = await client.PostAsJsonAsync("/api/categories", new { name = "  Pets ", type = "Expense", icon = "pets", color = "#8D6E63" });
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);
        var pets = (await res.Content.ReadFromJsonAsync<Category>())!;
        Assert.Equal(("Pets", "pets"), (pets.Name, pets.Icon));

        var put = await client.PutAsJsonAsync($"/api/categories/{pets.Id}", new { name = "Pet shop", type = "Expense", icon = "pets", color = "#795548" });
        Assert.Equal(HttpStatusCode.OK, put.StatusCode);
        var all = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        Assert.Contains(all, c => c is { Name: "Pet shop", Color: "#795548" });

        Assert.Equal(HttpStatusCode.NoContent, (await client.DeleteAsync($"/api/categories/{pets.Id}")).StatusCode);
    }

    [Fact]
    public async Task Nome_vazio_longo_ou_repetido_no_mesmo_tipo_e_recusado()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        Assert.Equal(HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/categories", new { name = "  ", type = "Expense" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await client.PostAsJsonAsync("/api/categories", new { name = new string('x', 41), type = "Expense" })).StatusCode);

        // "alimentação" já existe como despesa (categoria padrão), sem diferenciar maiúsculas.
        var dup = await client.PostAsJsonAsync("/api/categories", new { name = "ALIMENTAÇÃO", type = "Expense" });
        Assert.Equal(HttpStatusCode.Conflict, dup.StatusCode);
        Assert.Equal("Você já tem uma categoria com esse nome.", (await dup.Content.ReadFromJsonAsync<ErrorBody>())!.Error);

        // Mesmo nome em outro tipo é permitido.
        Assert.Equal(HttpStatusCode.Created,
            (await client.PostAsJsonAsync("/api/categories", new { name = "Alimentação", type = "Income" })).StatusCode);
    }

    [Fact]
    public async Task Tipo_so_muda_sem_lancamentos_e_categoria_com_lancamentos_nao_pode_ser_excluida()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var cats = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var lazer = cats.Single(c => c.Name == "Lazer");
        var acc = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        await client.PostAsJsonAsync("/api/transactions", new
        {
            accountId = acc.Id, categoryId = lazer.Id, description = "cinema", amount = 40m, type = "Expense", date = "2026-10-10",
        });

        var put = await client.PutAsJsonAsync($"/api/categories/{lazer.Id}", new { name = "Lazer", type = "Income" });
        Assert.Equal(HttpStatusCode.BadRequest, put.StatusCode);

        var del = await client.DeleteAsync($"/api/categories/{lazer.Id}");
        Assert.Equal(HttpStatusCode.Conflict, del.StatusCode);

        // Sem lançamentos o tipo pode mudar.
        var nova = (await (await client.PostAsJsonAsync("/api/categories", new { name = "Bicos", type = "Expense" }))
            .Content.ReadFromJsonAsync<Category>())!;
        Assert.Equal(HttpStatusCode.OK,
            (await client.PutAsJsonAsync($"/api/categories/{nova.Id}", new { name = "Bicos", type = "Income" })).StatusCode);
    }

    [Fact]
    public async Task Nao_edita_categoria_de_outro_usuario()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var other = await factory.CreateUserClientAsync("outro@teste.com");
        var deles = (await other.GetFromJsonAsync<List<Category>>("/api/categories"))![0];

        var res = await client.PutAsJsonAsync($"/api/categories/{deles.Id}", new { name = "Hack", type = deles.Type });
        Assert.Equal(HttpStatusCode.NotFound, res.StatusCode);
    }
}
