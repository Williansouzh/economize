using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace Financas.Api.Tests;

/// <summary>
/// Faz o papel da API de assinaturas do Mercado Pago: cria a assinatura "pending", devolve o estado
/// que o teste definir e guarda cada chamada (com a X-Idempotency-Key). Repetir a criação com a mesma
/// chave devolve a mesma assinatura, como o Mercado Pago real.
/// </summary>
public class FakeMercadoPago : HttpMessageHandler
{
    public record Call(string Method, string Path, string? IdempotencyKey, string Body);
    public record State(string Status, string ExternalReference, DateTime? NextPaymentDate);

    public List<Call> Calls { get; } = [];
    public Dictionary<string, State> Preapprovals { get; } = [];
    /// <summary>Cobrança mensal → assinatura.</summary>
    public Dictionary<string, string> AuthorizedPayments { get; } = [];
    /// <summary>Quantas das próximas chamadas falham com 500 (Mercado Pago fora do ar).</summary>
    public int FailNext { get; set; }
    private readonly Dictionary<string, string> _byKey = [];
    private int _next;

    public int Count(string method, string pathStart) { lock (Calls) return Calls.Count(c => c.Method == method && c.Path.StartsWith(pathStart)); }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(ct);
        var key = request.Headers.TryGetValues("X-Idempotency-Key", out var v) ? v.First() : null;
        var path = request.RequestUri!.AbsolutePath.TrimStart('/');
        var method = request.Method.Method;
        lock (Calls)
        {
            Calls.Add(new Call(method, path, key, body));
            if (FailNext > 0) { FailNext--; return new HttpResponseMessage(HttpStatusCode.InternalServerError); }

            if (method == "POST" && path == "preapproval")
            {
                if (key is null || !_byKey.TryGetValue(key, out var id))
                {
                    id = $"pre{++_next}";
                    var reference = JsonDocument.Parse(body).RootElement.GetProperty("external_reference").GetString()!;
                    Preapprovals[id] = new State("pending", reference, null);
                    if (key is not null) _byKey[key] = id;
                }
                return Json(id);
            }
            if (path.StartsWith("preapproval/"))
            {
                var id = path["preapproval/".Length..];
                if (!Preapprovals.TryGetValue(id, out var state)) return new HttpResponseMessage(HttpStatusCode.NotFound);
                if (method == "PUT") Preapprovals[id] = state with { Status = "cancelled" };
                return Json(id);
            }
            if (method == "GET" && path.StartsWith("authorized_payments/"))
                return new HttpResponseMessage(HttpStatusCode.OK)
                    { Content = JsonContent.Create(new { preapproval_id = AuthorizedPayments[path["authorized_payments/".Length..]] }) };
            return new HttpResponseMessage(HttpStatusCode.NotFound);
        }
    }

    private HttpResponseMessage Json(string id)
    {
        var s = Preapprovals[id];
        return new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = JsonContent.Create(new
            {
                id, status = s.Status, external_reference = s.ExternalReference,
                init_point = $"https://mp.test/checkout?pre={id}", next_payment_date = s.NextPaymentDate,
            }),
        };
    }
}
