using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

/// <summary>RN-26: o limite de login é contado no banco e vale igual em todas as réplicas.</summary>
public class LimiteDeLoginTests
{
    private static Task<HttpResponseMessage> LoginAsync(HttpClient c) =>
        c.PostAsJsonAsync("/api/auth/login", new { email = "ninguem@teste.com", password = "x" });

    [Fact]
    public async Task Limite_de_login_e_compartilhado_entre_replicas_e_libera_no_minuto_seguinte()
    {
        var db = $"financas_test_{Guid.NewGuid():N}";
        using var a = new ApiFactory { DatabaseName = db };
        using var b = new ApiFactory { DatabaseName = db, OwnsDatabase = false };
        var ca = a.CreateClient();
        var cb = b.CreateClient();

        // 6 tentativas numa réplica + 4 na outra = 10, o limite.
        for (var i = 0; i < 6; i++) Assert.Equal(HttpStatusCode.Unauthorized, (await LoginAsync(ca)).StatusCode);
        for (var i = 0; i < 4; i++) Assert.Equal(HttpStatusCode.Unauthorized, (await LoginAsync(cb)).StatusCode);

        var blockedA = await LoginAsync(ca);
        var blockedB = await LoginAsync(cb);
        Assert.Equal(HttpStatusCode.TooManyRequests, blockedA.StatusCode);
        Assert.Equal(HttpStatusCode.TooManyRequests, blockedB.StatusCode);
        Assert.InRange(int.Parse(blockedA.Headers.GetValues("Retry-After").Single()), 1, 60);

        // Janela seguinte: libera nas duas réplicas.
        a.Clock.Advance(TimeSpan.FromMinutes(1));
        b.Clock.Advance(TimeSpan.FromMinutes(1));
        Assert.Equal(HttpStatusCode.Unauthorized, (await LoginAsync(ca)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await LoginAsync(cb)).StatusCode);
    }

    [Fact]
    public async Task Tentativas_simultaneas_nao_se_perdem()
    {
        using var f = new ApiFactory();
        var c = f.CreateClient();

        var results = await Task.WhenAll(Enumerable.Range(0, 15).Select(_ => LoginAsync(c)));

        // Incremento atômico: exatamente 10 passam, mesmo chegando todas juntas.
        Assert.Equal(10, results.Count(r => r.StatusCode == HttpStatusCode.Unauthorized));
        Assert.Equal(5, results.Count(r => r.StatusCode == HttpStatusCode.TooManyRequests));
    }
}
