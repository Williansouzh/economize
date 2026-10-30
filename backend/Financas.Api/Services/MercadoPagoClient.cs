using System.Net;
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
/// O Mercado Pago respondeu e recusou o pedido (dados inválidos, recurso que não existe): repetir não muda
/// nada. Fora do ar, limite de chamadas ou credencial errada continuam <see cref="HttpRequestException"/>
/// comum, que vale tentar de novo. <see cref="Reason"/> é a mensagem do Mercado Pago, para o log.
/// </summary>
public class MercadoPagoRefusedException(HttpStatusCode status, string? reason)
    : HttpRequestException($"Mercado Pago recusou ({(int)status}): {reason}", null, status)
{
    public string? Reason => reason;
}

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
        await EnsureOkAsync(res, ct);
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync(ct));
        return doc.RootElement.TryGetProperty("preapproval_id", out var p) ? p.GetString() : null;
    }

    private async Task<MpPreapproval> SendAsync(HttpMethod method, string path, object? body, Guid? idempotencyKey, CancellationToken ct)
    {
        using var res = await http.SendAsync(Request(method, path, body, idempotencyKey), ct);
        await EnsureOkAsync(res, ct); // falha vira HttpRequestException: quem chama decide (502 ou nova tentativa)
        return (await res.Content.ReadFromJsonAsync<MpPreapproval>(Json, ct))!;
    }

    private static async Task EnsureOkAsync(HttpResponseMessage res, CancellationToken ct)
    {
        if (res.IsSuccessStatusCode) return;
        if (res.StatusCode is not (HttpStatusCode.BadRequest or HttpStatusCode.NotFound or HttpStatusCode.UnprocessableEntity))
            res.EnsureSuccessStatusCode();
        string? reason = null;
        try
        {
            using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync(ct));
            if (doc.RootElement.TryGetProperty("message", out var m)) reason = m.ToString();
        }
        catch (JsonException) { }
        throw new MercadoPagoRefusedException(res.StatusCode, reason is { Length: > 300 } ? reason[..300] : reason);
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
