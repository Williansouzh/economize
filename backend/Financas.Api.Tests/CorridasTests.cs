using System.Net;
using System.Net.Http.Json;
using Financas.Api.Data;
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
}
