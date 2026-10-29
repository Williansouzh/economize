using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Tokens;

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

    private static async Task<(HttpStatusCode Status, string? Token)> RenewAsync(HttpClient client)
    {
        var res = await client.PostAsync("/api/me/token", null);
        if (!res.IsSuccessStatusCode) return (res.StatusCode, null);
        var token = (await res.Content.ReadFromJsonAsync<ApiFactory.AuthBody>())!.Token;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return (res.StatusCode, token);
    }

    [Fact]
    public async Task Renovar_funciona_ate_90_dias_depois_do_login_e_depois_pede_a_senha()
    {
        // Antes, renovar dava um token novo de 14 dias sem fim: um token roubado valia para sempre.
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        factory.Clock.Advance(TimeSpan.FromDays(80));
        Assert.Equal(HttpStatusCode.OK, (await RenewAsync(client)).Status);
        Assert.Equal(HttpStatusCode.OK, (await client.GetAsync("/api/me")).StatusCode);

        factory.Clock.Advance(TimeSpan.FromDays(11)); // 91 dias desde o login, mesmo renovando no meio
        var res = await client.PostAsync("/api/me/token", null);
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
        Assert.Contains("Entre de novo", (await res.Content.ReadFromJsonAsync<ErrorBody>())!.Error);

        // Entrar com a senha começa outros 90 dias.
        var denovo = await LoginAsync(factory);
        Assert.Equal(HttpStatusCode.OK, (await RenewAsync(denovo)).Status);
    }

    [Fact]
    public async Task Token_renovado_nao_passa_do_fim_da_sessao()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        factory.Clock.Advance(TimeSpan.FromDays(85));
        var (_, token) = await RenewAsync(client);

        // Faltam 5 dias para os 90: o token novo vale 5 dias, e não 14.
        var validFor = new JwtSecurityTokenHandler().ReadJwtToken(token).ValidTo - DateTime.UtcNow;
        Assert.InRange(validFor, TimeSpan.FromDays(4.9), TimeSpan.FromDays(5.01));
    }

    [Fact]
    public async Task Token_de_antes_da_regra_conta_os_90_dias_a_partir_da_renovacao()
    {
        // Ninguém é desconectado no dia do deploy: o token sem a data do login vale como login agora.
        using var factory = new ApiFactory();
        await factory.CreateUserClientAsync();
        var config = factory.Services.GetRequiredService<IConfiguration>();
        var jwt = config.GetSection("Jwt");
        var id = (await LoginAsync(factory)).DefaultRequestHeaders.Authorization!.Parameter!;
        var userId = new JwtSecurityTokenHandler().ReadJwtToken(id).Claims.First(c => c.Type is "nameid" or ClaimTypes.NameIdentifier).Value;
        var old = new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(jwt["Issuer"], jwt["Audience"],
            [new Claim(ClaimTypes.NameIdentifier, userId), new Claim("tv", "0")], expires: DateTime.UtcNow.AddDays(14),
            signingCredentials: new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Key"]!)), SecurityAlgorithms.HmacSha256)));
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", old);

        factory.Clock.Advance(TimeSpan.FromDays(400)); // muito tempo depois do cadastro
        Assert.Equal(HttpStatusCode.OK, (await RenewAsync(client)).Status);
        factory.Clock.Advance(TimeSpan.FromDays(89));
        Assert.Equal(HttpStatusCode.OK, (await RenewAsync(client)).Status);
        factory.Clock.Advance(TimeSpan.FromDays(2));
        Assert.Equal(HttpStatusCode.Unauthorized, (await RenewAsync(client)).Status);
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
