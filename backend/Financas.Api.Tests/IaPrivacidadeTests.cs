using System.Net;
using System.Net.Http.Json;
using System.Text.RegularExpressions;

namespace Financas.Api.Tests;

/// <summary>RN-16: o usuário pode tirar as descrições das despesas do que vai para o DeepSeek.</summary>
public class IaPrivacidadeTests
{
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name);

    private const string Insights = """{"summary":"ok","alerts":[],"tips":[],"potentialSavings":0,"healthScore":50}""";

    private static async Task<HttpClient> UserWithExpenseAsync(ApiFactory f, string description)
    {
        var c = await f.CreateUserClientAsync();
        var cats = (await c.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var acc = (await c.GetFromJsonAsync<List<Account>>("/api/accounts"))![0];
        var res = await c.PostAsJsonAsync("/api/transactions", new
        {
            accountId = acc.Id, categoryId = cats.First(x => x.Type == "Expense").Id,
            description, amount = 350m, type = "Expense", date = "2026-10-10",
        });
        res.EnsureSuccessStatusCode();
        return c;
    }

    // O corpo vai para o DeepSeek como JSON: acentos e aspas chegam escapados.
    private static string Sent(ApiFactory f, int i) => Regex.Unescape(f.DeepSeekCalls[i]);

    [Fact]
    public async Task Insights_sem_descricoes_nao_mandam_a_descricao_mas_mandam_o_valor()
    {
        using var f = new ApiFactory { DeepSeekReply = Insights };
        var c = await UserWithExpenseAsync(f, "Consulta Dra Fulana psiquiatra");

        var off = await c.PostAsJsonAsync("/api/insights", new { month = "2026-10", includeDescriptions = false });
        var on = await c.PostAsJsonAsync("/api/insights", new { month = "2026-10" });

        Assert.Equal(HttpStatusCode.OK, off.StatusCode);
        Assert.Equal(HttpStatusCode.OK, on.StatusCode);
        Assert.DoesNotContain("Fulana", Sent(f, 0));
        Assert.Contains("350,00", Sent(f, 0));
        Assert.Contains("Fulana", Sent(f, 1)); // padrão continua enviando, como antes
    }

    [Fact]
    public async Task Chat_tambem_respeita_a_escolha()
    {
        using var f = new ApiFactory { DeepSeekReply = "Você gastou R$ 350,00." };
        var c = await UserWithExpenseAsync(f, "Presente para Ana Beatriz");

        var res = await c.PostAsJsonAsync("/api/insights/chat",
            new { question = "Quanto gastei?", month = "2026-10", includeDescriptions = false });

        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        Assert.DoesNotContain("Ana Beatriz", Sent(f, 0));
    }
}
