using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using Financas.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Financas.Api.Tests;

// ---------- RN-51: Economizze Plus (mês grátis, limites do grátis e assinatura pelo Mercado Pago) ----------
public class PlanoPlusTests
{
    private record PlanBody(string Plan, string? Source, DateTime? TrialEndsAt, DateTime? PaidUntil, string? SubscriptionStatus, decimal MonthlyPrice);
    private record Subscribed(Guid SubscriptionId, string InitPoint);
    private record ErrorBody(string Error);

    private static Task<HttpResponseMessage[]> AllAtOnce(int count, Func<int, Task<HttpResponseMessage>> send) =>
        Task.WhenAll(Enumerable.Range(0, count).Select(i => Task.Run(() => send(i))));

    private static async Task<PlanBody> PlanOf(HttpClient c) => (await c.GetFromJsonAsync<PlanBody>("/api/me/plan"))!;

    // ---------- Mês grátis e o que muda no grátis ----------

    [Fact]
    public async Task Conta_nova_tem_30_dias_de_Plus_sem_cartao_e_depois_vira_gratis()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();

        var plan = await PlanOf(client);
        Assert.Equal(("plus", "trial"), (plan.Plan, plan.Source));
        Assert.Equal(4.00m, plan.MonthlyPrice);
        Assert.Equal(factory.Clock.GetUtcNow().UtcDateTime.AddDays(30), plan.TrialEndsAt!.Value, TimeSpan.FromSeconds(5));

        factory.Clock.Advance(TimeSpan.FromDays(31));
        Assert.Equal("free", (await PlanOf(client)).Plan);
    }

    [Fact]
    public async Task No_gratis_whatsapp_pdf_e_perfil_de_empresa_pedem_o_Plus()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        factory.Clock.Advance(TimeSpan.FromDays(31));

        foreach (var res in new[]
                 {
                     await client.PostAsync("/api/me/whatsapp-code", null),
                     await client.PostAsync("/api/insights/quota/whatsapp", null),
                     await client.PostAsJsonAsync("/api/profiles", new { name = "Minha MEI", isMei = true }),
                 })
        {
            Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);
            Assert.Contains("Plus", (await res.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
        }
        // O que é só organizar o dinheiro continua liberado.
        Assert.Equal(HttpStatusCode.Created, (await client.PostAsJsonAsync("/api/goals", new { name = "Viagem", target = 1000m })).StatusCode);
    }

    [Fact]
    public async Task No_gratis_sao_3_perguntas_por_dia_e_1_analise_por_semana()
    {
        using var factory = new ApiFactory { DeepSeekReply = """{"summary":"ok","alerts":[],"tips":[],"potentialSavings":0,"healthScore":50}""" };
        var client = await factory.CreateUserClientAsync();
        factory.Clock.Advance(TimeSpan.FromDays(31)); // 17/11/2026, uma terça

        for (var i = 0; i < 3; i++)
            Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/insights/chat", new { question = "quanto gastei?" })).StatusCode);
        var fourth = await client.PostAsJsonAsync("/api/insights/chat", new { question = "e agora?" });
        Assert.Equal((HttpStatusCode)429, fourth.StatusCode);
        Assert.Contains("Plus", (await fourth.Content.ReadFromJsonAsync<ErrorBody>())!.Error);

        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/insights", new { month = "2026-11" })).StatusCode);
        Assert.Equal((HttpStatusCode)429, (await client.PostAsJsonAsync("/api/insights", new { month = "2026-10" })).StatusCode);
        factory.Clock.Advance(TimeSpan.FromDays(6)); // segunda-feira seguinte: semana nova
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/insights", new { month = "2026-10" })).StatusCode);
    }

    // ---------- Assinar (chamadas que o app faz e que a API faz ao Mercado Pago) ----------

    private static HttpRequestMessage Subscribe(string? key) =>
        new(HttpMethod.Post, "/api/billing/subscribe") { Headers = { { "Idempotency-Key", key ?? "" } } };

    [Fact]
    public async Task Assinar_cria_a_assinatura_de_4_reais_no_Mercado_Pago_com_chave_UUID_e_sem_dado_pessoal_na_referencia()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync("ana@teste.com");

        var res = await client.SendAsync(Subscribe("toque-1"));

        res.EnsureSuccessStatusCode();
        var sub = (await res.Content.ReadFromJsonAsync<Subscribed>())!;
        Assert.StartsWith("https://mp.test/checkout", sub.InitPoint);
        var call = Assert.Single(factory.MercadoPago.Calls);
        Assert.True(Guid.TryParse(call.IdempotencyKey, out var key) && key.ToString()[14] == '4'); // UUID v4
        Assert.Contains("\"transaction_amount\":4.00", call.Body);
        Assert.Contains($"\"external_reference\":\"{sub.SubscriptionId}\"", call.Body);
        Assert.DoesNotContain("ana@teste.com", call.IdempotencyKey);
    }

    [Fact]
    public async Task O_mesmo_pedido_de_assinatura_repetido_e_ao_mesmo_tempo_cria_uma_assinatura()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();

        var first = await (await client.SendAsync(Subscribe("toque-1"))).Content.ReadFromJsonAsync<Subscribed>();
        var again = await (await client.SendAsync(Subscribe("toque-1"))).Content.ReadFromJsonAsync<Subscribed>();
        var together = await AllAtOnce(3, _ => client.SendAsync(Subscribe("toque-2")));

        Assert.Equal(first, again); // mesma resposta
        Assert.All(together, r => Assert.True(r.StatusCode is HttpStatusCode.OK));
        var pages = await Task.WhenAll(together.Select(async r => (await r.Content.ReadFromJsonAsync<Subscribed>())!.InitPoint));
        Assert.Single(pages.Distinct());
        using var scope = factory.Services.CreateScope();
        Assert.Equal(2, await scope.ServiceProvider.GetRequiredService<AppDbContext>().Subscriptions.CountAsync());
    }

    [Fact]
    public async Task Nova_tentativa_depois_de_falha_do_Mercado_Pago_manda_a_mesma_chave()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();
        factory.MercadoPago.FailNext = 1;

        Assert.Equal(HttpStatusCode.BadGateway, (await client.SendAsync(Subscribe("toque-1"))).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await client.SendAsync(Subscribe("toque-1"))).StatusCode);

        var keys = factory.MercadoPago.Calls.Where(c => c.Method == "POST").Select(c => c.IdempotencyKey).ToList();
        Assert.Equal(2, keys.Count);
        Assert.Equal(keys[0], keys[1]); // o Mercado Pago vê a mesma operação, não uma segunda cobrança
        Assert.Single(factory.MercadoPago.Preapprovals);
    }

    // ---------- Webhook ----------

    private static async Task<(string PreapprovalId, Guid SubscriptionId)> SubscribedAsync(ApiFactory factory, HttpClient client)
    {
        var sub = (await (await client.SendAsync(Subscribe(Guid.NewGuid().ToString()))).Content.ReadFromJsonAsync<Subscribed>())!;
        return (factory.MercadoPago.Preapprovals.Single(p => p.Value.ExternalReference == sub.SubscriptionId.ToString()).Key, sub.SubscriptionId);
    }

    private static void Authorize(ApiFactory factory, string preapprovalId, DateTime next) =>
        factory.MercadoPago.Preapprovals[preapprovalId] = factory.MercadoPago.Preapprovals[preapprovalId] with
        { Status = "authorized", NextPaymentDate = next };

    /// <summary>Aviso como o Mercado Pago manda: x-signature = ts e HMAC de "id:..;request-id:..;ts:..;".</summary>
    private static HttpRequestMessage Webhook(string type, string dataId, string notificationId, string? secret = ApiFactory.MpWebhookSecret)
    {
        var requestId = Guid.NewGuid().ToString();
        var ts = "1793300000000";
        var v1 = Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret ?? ""),
            Encoding.UTF8.GetBytes($"id:{dataId.ToLowerInvariant()};request-id:{requestId};ts:{ts};"))).ToLowerInvariant();
        return new HttpRequestMessage(HttpMethod.Post, $"/api/pagamentos/webhook?data.id={dataId}&type={type}")
        {
            Headers = { { "x-signature", $"ts={ts},v1={v1}" }, { "x-request-id", requestId } },
            Content = JsonContent.Create(new { id = notificationId, type, action = "updated", data = new { id = dataId } }),
        };
    }

    [Fact]
    public async Task Aviso_com_assinatura_errada_e_recusado_e_nao_libera_nada()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();
        factory.Clock.Advance(TimeSpan.FromDays(31));
        var (pre, _) = await SubscribedAsync(factory, client);
        Authorize(factory, pre, factory.Clock.GetUtcNow().UtcDateTime.AddDays(30));

        var forged = await factory.CreateClient().SendAsync(Webhook("subscription_preapproval", pre, "n1", secret: "outro-segredo"));

        Assert.Equal(HttpStatusCode.Unauthorized, forged.StatusCode);
        Assert.Equal("free", (await PlanOf(client)).Plan);
        Assert.Equal(0, factory.MercadoPago.Count("GET", "preapproval/"));
    }

    [Fact]
    public async Task Aviso_valido_libera_o_Plus_com_o_estado_buscado_no_Mercado_Pago()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();
        factory.Clock.Advance(TimeSpan.FromDays(31));
        var (pre, _) = await SubscribedAsync(factory, client);
        var next = factory.Clock.GetUtcNow().UtcDateTime.AddDays(30);
        Authorize(factory, pre, next);

        var res = await factory.CreateClient().SendAsync(Webhook("subscription_preapproval", pre, "n1"));

        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var plan = await PlanOf(client);
        Assert.Equal(("plus", "subscription", "authorized"), (plan.Plan, plan.Source, plan.SubscriptionStatus));
        Assert.Equal(next, plan.PaidUntil!.Value, TimeSpan.FromSeconds(1));
    }

    [Fact]
    public async Task O_mesmo_aviso_duas_vezes_e_duas_vezes_ao_mesmo_tempo_tem_efeito_uma_vez()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();
        factory.Clock.Advance(TimeSpan.FromDays(31));
        var (pre, _) = await SubscribedAsync(factory, client);
        Authorize(factory, pre, factory.Clock.GetUtcNow().UtcDateTime.AddDays(30));
        var anon = factory.CreateClient();

        var seguidos = new[] { await anon.SendAsync(Webhook("subscription_preapproval", pre, "n1")), await anon.SendAsync(Webhook("subscription_preapproval", pre, "n1")) };
        var juntos = await AllAtOnce(2, _ => anon.SendAsync(Webhook("subscription_preapproval", pre, "n2")));

        // Todos recebem 200 (senão o Mercado Pago reenviaria), mas cada aviso é processado uma vez:
        // uma busca no Mercado Pago por aviso, e nenhuma pela cópia.
        Assert.All(seguidos.Concat(juntos), r => Assert.Equal(HttpStatusCode.OK, r.StatusCode));
        Assert.Equal(2, factory.MercadoPago.Count("GET", "preapproval/"));
        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        Assert.Equal(2, await db.PaymentEvents.CountAsync());
        Assert.Equal("plus", (await PlanOf(client)).Plan);
    }

    [Fact]
    public async Task Se_o_Mercado_Pago_falhar_o_aviso_nao_fica_marcado_e_o_reenvio_processa()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();
        factory.Clock.Advance(TimeSpan.FromDays(31));
        var (pre, _) = await SubscribedAsync(factory, client);
        Authorize(factory, pre, factory.Clock.GetUtcNow().UtcDateTime.AddDays(30));
        var anon = factory.CreateClient();
        factory.MercadoPago.FailNext = 1;

        Assert.Equal(HttpStatusCode.ServiceUnavailable, (await anon.SendAsync(Webhook("subscription_preapproval", pre, "n1"))).StatusCode);
        Assert.Equal("free", (await PlanOf(client)).Plan);
        Assert.Equal(HttpStatusCode.OK, (await anon.SendAsync(Webhook("subscription_preapproval", pre, "n1"))).StatusCode);
        Assert.Equal("plus", (await PlanOf(client)).Plan);
    }

    [Fact]
    public async Task Aviso_de_cobranca_mensal_atualiza_a_assinatura_dela()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();
        factory.Clock.Advance(TimeSpan.FromDays(31));
        var (pre, _) = await SubscribedAsync(factory, client);
        Authorize(factory, pre, factory.Clock.GetUtcNow().UtcDateTime.AddDays(30));
        factory.MercadoPago.AuthorizedPayments["pay77"] = pre;

        var res = await factory.CreateClient().SendAsync(Webhook("subscription_authorized_payment", "pay77", "n9"));

        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        Assert.Equal("plus", (await PlanOf(client)).Plan);
    }

    [Fact]
    public async Task Sem_a_chave_secreta_configurada_o_webhook_recusa_tudo()
    {
        using var factory = new ApiFactory();
        var res = await factory.CreateClient().SendAsync(Webhook("subscription_preapproval", "pre1", "n1"));
        Assert.Equal(HttpStatusCode.ServiceUnavailable, res.StatusCode);
    }

    // ---------- Cancelar ----------

    [Fact]
    public async Task Cancelar_mantem_o_Plus_ate_o_fim_do_periodo_pago_e_manda_chave_ao_Mercado_Pago()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();
        factory.Clock.Advance(TimeSpan.FromDays(31));
        var (pre, _) = await SubscribedAsync(factory, client);
        Authorize(factory, pre, factory.Clock.GetUtcNow().UtcDateTime.AddDays(20));
        await factory.CreateClient().SendAsync(Webhook("subscription_preapproval", pre, "n1"));

        Assert.Equal(HttpStatusCode.OK, (await client.PostAsync("/api/billing/cancel", null)).StatusCode);

        var put = Assert.Single(factory.MercadoPago.Calls, c => c.Method == "PUT");
        Assert.True(Guid.TryParse(put.IdempotencyKey, out _));
        var plan = await PlanOf(client);
        Assert.Equal(("plus", "cancelled"), (plan.Plan, plan.SubscriptionStatus)); // ainda dentro do que foi pago
        factory.Clock.Advance(TimeSpan.FromDays(21));
        Assert.Equal("free", (await PlanOf(client)).Plan);
    }

    [Fact]
    public async Task Excluir_a_conta_cancela_a_assinatura_no_Mercado_Pago_antes()
    {
        using var factory = new ApiFactory { UseMercadoPago = true };
        var client = await factory.CreateUserClientAsync();
        var (pre, _) = await SubscribedAsync(factory, client);
        Authorize(factory, pre, factory.Clock.GetUtcNow().UtcDateTime.AddDays(30));
        await factory.CreateClient().SendAsync(Webhook("subscription_preapproval", pre, "n1"));

        var res = await client.SendAsync(new HttpRequestMessage(HttpMethod.Delete, "/api/me") { Content = JsonContent.Create(new { password = ApiFactory.Password }) });

        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);
        Assert.Equal("cancelled", factory.MercadoPago.Preapprovals[pre].Status);
    }
}
