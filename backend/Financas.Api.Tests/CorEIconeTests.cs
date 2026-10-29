using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

// ---------- Cor e ícone de contas, categorias e metas têm formato e tamanho limitados ----------
public class CorEIconeTests
{
    private static readonly string Enorme = new('a', 100_000);

    public static TheoryData<string?, string?> Invalidos => new()
    {
        { Enorme, null },                 // antes: aceito (texto de qualquer tamanho no banco)
        { "vermelho", null },
        { "#12345", null },
        { "#1234567890", null },
        { null, Enorme },                 // antes: 500 na conta, aceito na categoria
        { null, "Ícone com espaço" },
        { null, "<script>" },
    };

    [Theory]
    [MemberData(nameof(Invalidos))]
    public async Task Categoria_conta_e_meta_recusam_cor_ou_icone_invalido_com_400(string? color, string? icon)
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/categories",
            new { name = "Pets", type = "Expense", color, icon })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/accounts",
            new { name = "Banco", initialBalance = 0m, kind = "Regular", color, icon })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await client.PostAsJsonAsync("/api/goals",
            new { name = "Viagem", target = 1000m, color, icon })).StatusCode);
    }

    [Fact]
    public async Task Formatos_que_o_app_usa_continuam_aceitos()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        Assert.Equal(HttpStatusCode.Created, (await client.PostAsJsonAsync("/api/categories",
            new { name = "Pets", type = "Expense", color = "#668E93", icon = "inventory_2" })).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await client.PostAsJsonAsync("/api/accounts",
            new { name = "Banco", initialBalance = 0m, kind = "Regular", color = "#0c7a68", icon = "account_balance" })).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await client.PostAsJsonAsync("/api/goals",
            new { name = "Viagem", target = 1000m, color = "#3080BCFF", icon = "flight" })).StatusCode);
        // Sem cor e ícone: ficam os padrões.
        Assert.Equal(HttpStatusCode.Created, (await client.PostAsJsonAsync("/api/categories",
            new { name = "Outros 2", type = "Income" })).StatusCode);
    }

    [Fact]
    public async Task Email_enorme_no_esqueci_a_senha_nao_derruba_a_api()
    {
        // A chave do limite por e-mail tem até 120 caracteres: o e-mail entra como hash.
        using var factory = new ApiFactory();
        var res = await factory.CreateClient().PostAsJsonAsync("/api/auth/forgot-password", new { email = new string('a', 300) + "@teste.com" });
        Assert.Equal(HttpStatusCode.Accepted, res.StatusCode);
    }
}
