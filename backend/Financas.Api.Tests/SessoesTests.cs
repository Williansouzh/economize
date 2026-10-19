using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

// ---------- RN-32: senha mínima, renovação do token e "Sair de todos os aparelhos" ----------
public class SessoesTests
{
    private record ErrorBody(string Error);

    private static async Task<HttpClient> LoginAsync(ApiFactory factory, string email = "user@teste.com")
    {
        var client = factory.CreateClient();
        var res = await client.PostAsJsonAsync("/api/auth/login", new { email, password = ApiFactory.Password });
        res.EnsureSuccessStatusCode();
        var auth = await res.Content.ReadFromJsonAsync<ApiFactory.AuthBody>();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth!.Token);
        return client;
    }

    [Fact]
    public async Task Cadastro_exige_senha_de_8_caracteres()
    {
        using var factory = new ApiFactory();
        var client = factory.CreateClient();

        var curta = await client.PostAsJsonAsync("/api/auth/register", new { name = "Ana", email = "ana@teste.com", password = "1234567" });
        Assert.Equal(HttpStatusCode.BadRequest, curta.StatusCode);
        Assert.Contains("8 caracteres", (await curta.Content.ReadFromJsonAsync<ErrorBody>())!.Error);

        var ok = await client.PostAsJsonAsync("/api/auth/register", new { name = "Ana", email = "ana@teste.com", password = "12345678" });
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
    }

    [Fact]
    public async Task Renovar_devolve_um_token_novo_que_funciona()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        var res = await client.PostAsync("/api/me/token", null);
        res.EnsureSuccessStatusCode();
        var auth = await res.Content.ReadFromJsonAsync<ApiFactory.AuthBody>();

        var novo = factory.CreateClient();
        novo.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", auth!.Token);
        Assert.Equal(HttpStatusCode.OK, (await novo.GetAsync("/api/me")).StatusCode);
    }

    [Fact]
    public async Task Sair_de_todos_os_aparelhos_derruba_todas_as_sessoes_do_usuario_e_so_dele()
    {
        using var factory = new ApiFactory();
        var celular = await factory.CreateUserClientAsync();
        var navegador = await LoginAsync(factory);
        var outro = await factory.CreateUserClientAsync("outro@teste.com");

        Assert.Equal(HttpStatusCode.NoContent, (await navegador.DeleteAsync("/api/me/sessions")).StatusCode);

        Assert.Equal(HttpStatusCode.Unauthorized, (await celular.GetAsync("/api/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await navegador.GetAsync("/api/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await navegador.PostAsync("/api/me/token", null)).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await outro.GetAsync("/api/me")).StatusCode);

        // Entrar de novo gera um token que vale.
        var denovo = await LoginAsync(factory);
        Assert.Equal(HttpStatusCode.OK, (await denovo.GetAsync("/api/me")).StatusCode);
    }

    [Fact]
    public async Task Token_de_conta_excluida_deixa_de_valer()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var outroAparelho = await LoginAsync(factory);

        var delete = new HttpRequestMessage(HttpMethod.Delete, "/api/me") { Content = JsonContent.Create(new { password = ApiFactory.Password }) };
        Assert.Equal(HttpStatusCode.NoContent, (await client.SendAsync(delete)).StatusCode);

        Assert.Equal(HttpStatusCode.Unauthorized, (await outroAparelho.GetAsync("/api/accounts")).StatusCode);
    }
}
