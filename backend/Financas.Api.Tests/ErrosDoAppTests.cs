using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

// ---------- Erros que o app envia (POST /api/client-errors, sem login) ----------
public class ErrosDoAppTests
{
    [Fact]
    public void Erro_do_app_nao_forja_linhas_no_log()
    {
        // A rota /api/client-errors aceita chamadas sem login: uma quebra de linha na mensagem
        // criaria uma linha falsa no log ("info: ... Login do admin ok").
        var forjada = "falhou\ninfo: Microsoft.Hosting.Lifetime[0]\r\n      Login do admin ok\u001b[31m";
        Assert.DoesNotContain('\n', Endpoints.PlanningEndpoints.OneLine(forjada));
        Assert.DoesNotContain('\u001b', Endpoints.PlanningEndpoints.OneLine(forjada));

        // A pilha continua em várias linhas, mas todas recuadas: nenhuma começa como linha do log.
        var pilha = Endpoints.PlanningEndpoints.Indented("at main.dart 10\ninfo: falsa\r\nat x");
        Assert.All(pilha.Split('\n'), linha => Assert.StartsWith("  ", linha));
    }

    [Fact]
    public async Task Rota_de_erros_do_app_continua_aceitando()
    {
        using var factory = new ApiFactory();
        var res = await factory.CreateClient().PostAsJsonAsync("/api/client-errors",
            new { platform = "web", version = "1.5.1", message = "a\nb", stack = "x\ny" });
        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);
    }
}
