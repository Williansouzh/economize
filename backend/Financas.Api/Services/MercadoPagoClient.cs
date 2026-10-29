using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Financas.Api.Services;

/// <summary>Assinatura no Mercado Pago, como a API devolve (só os campos que o app usa).</summary>
public record MpPreapproval(
    string Id,
    string Status,
    [property: JsonPropertyName("external_reference")] string? ExternalReference,
    [property: JsonPropertyName("init_point")] string? InitPoint,
    [property: JsonPropertyName("next_payment_date")] DateTime? NextPaymentDate);

/// <summary>
/// API de assinaturas do Mercado Pago (preapproval). Toda chamada que cria ou muda algo leva
/// X-Idempotency-Key: repetir a mesma operação (timeout, nova tentativa) não cria uma segunda cobrança.
/// </summary>
public class MercadoPagoClient(HttpClient http, IConfiguration config)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public bool IsConfigured => !string.IsNullOrWhiteSpace(config["MercadoPago:AccessToken"]);

    public Task<MpPreapproval> CreatePreapprovalAsync(object body, Guid idempotencyKey, CancellationToken ct) =>
        SendAsync(HttpMethod.Post, "preapproval", body, idempotencyKey, ct);

    public Task<MpPreapproval> GetPreapprovalAsync(string id, CancellationToken ct) =>
        SendAsync(HttpMethod.Get, $"preapproval/{Uri.EscapeDataString(id)}", null, null, ct);

    public Task<MpPreapproval> CancelPreapprovalAsync(string id, Guid idempotencyKey, CancellationToken ct) =>
        SendAsync(HttpMethod.Put, $"preapproval/{Uri.EscapeDataString(id)}", new { status = "cancelled" }, idempotencyKey, ct);

    /// <summary>Cobrança mensal de uma assinatura: devolve o id da assinatura a que ela pertence.</summary>
    public async Task<string?> GetAuthorizedPaymentPreapprovalIdAsync(string id, CancellationToken ct)
    {
        using var res = await http.SendAsync(Request(HttpMethod.Get, $"authorized_payments/{Uri.EscapeDataString(id)}", null, null), ct);
        res.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync(ct));
        return doc.RootElement.TryGetProperty("preapproval_id", out var p) ? p.GetString() : null;
    }

    private async Task<MpPreapproval> SendAsync(HttpMethod method, string path, object? body, Guid? idempotencyKey, CancellationToken ct)
    {
        using var res = await http.SendAsync(Request(method, path, body, idempotencyKey), ct);
        res.EnsureSuccessStatusCode(); // falha vira HttpRequestException: quem chama decide (502 ou nova tentativa)
        return (await res.Content.ReadFromJsonAsync<MpPreapproval>(Json, ct))!;
    }

    private HttpRequestMessage Request(HttpMethod method, string path, object? body, Guid? idempotencyKey)
    {
        var req = new HttpRequestMessage(method, path);
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", config["MercadoPago:AccessToken"]);
        if (idempotencyKey is { } key) req.Headers.Add("X-Idempotency-Key", key.ToString());
        if (body is not null) req.Content = JsonContent.Create(body);
        return req;
    }
}
