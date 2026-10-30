using System.Globalization;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Financas.Api.Data;
using Financas.Api.Models;
using Financas.Api.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Endpoints;

/// <summary>
/// RN-51: assinatura do Economizze Plus pelo Mercado Pago. O app abre a página de pagamento do Mercado
/// Pago (nenhum dado de cartão passa por aqui) e o Mercado Pago avisa pelo webhook. O estado da
/// assinatura é sempre buscado na API do Mercado Pago, nunca tirado do aviso.
/// </summary>
public static class BillingEndpoints
{
    public record PlanDto(string Plan, string? Source, DateTime? TrialEndsAt, DateTime? PaidUntil, string? SubscriptionStatus,
        decimal MonthlyPrice);
    public record SubscribeResponse(Guid SubscriptionId, string InitPoint);

    public static void MapBillingEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/me/plan", async (ClaimsPrincipal user, PlanService plans, AppDbContext db, MercadoPagoClient mp,
            AppClock clock, ILoggerFactory logs, CancellationToken ct) =>
        {
            await SyncPendingAsync(user.UserId(), db, mp, clock, logs.CreateLogger("MercadoPago"), ct);
            var p = await plans.GetAsync(user.UserId());
            return new PlanDto(p.IsPlus ? "plus" : "free", p.Source, p.TrialEndsAt, p.PaidUntil, p.SubscriptionStatus, plans.MonthlyPrice);
        }).RequireAuthorization().WithTags("Plano");

        var billing = app.MapGroup("/api/billing").RequireAuthorization().WithTags("Plano");

        // Idempotency-Key do app: repetir o pedido (toque duplo, nova tentativa) devolve a mesma assinatura.
        // Para o Mercado Pago vai outra chave, um UUID v4 criado uma vez por assinatura e reaproveitado
        // em cada nova tentativa (Subscription.CreateKey). Nenhuma chave usa e-mail ou CPF.
        billing.MapPost("/subscribe", async ([FromHeader(Name = "Idempotency-Key")] string? clientKey, ClaimsPrincipal user,
            AppDbContext db, PlanService plans, MercadoPagoClient mp, AppClock clock, IConfiguration config, ILoggerFactory logs,
            CancellationToken ct) =>
        {
            var log = logs.CreateLogger("MercadoPago");
            if (!mp.IsConfigured)
                return Results.Json(new { error = "A assinatura ainda não está disponível. Tente mais tarde." }, statusCode: 503);
            var key = string.IsNullOrWhiteSpace(clientKey) ? null : clientKey.Trim();
            if (key is { Length: > 100 }) return Results.BadRequest(new { error = "Idempotency-Key pode ter no máximo 100 caracteres." });
            var uid = user.UserId();

            var plan = await plans.GetAsync(uid);
            if (plan.SubscriptionStatus == "authorized")
                return Results.Conflict(new { error = "Você já assina o Plus." });

            // Mesmo pedido de antes, ou uma assinatura ainda não paga criada há pouco: devolve a mesma página.
            var since = clock.UtcNow.AddHours(-24);
            var sub = key is not null
                ? await db.Subscriptions.FirstOrDefaultAsync(s => s.UserId == uid && s.ClientKey == key, ct)
                : await db.Subscriptions.Where(s => s.UserId == uid && (s.Status == "pending" || s.Status == "creating") && s.CreatedAt > since)
                    .OrderByDescending(s => s.CreatedAt).FirstOrDefaultAsync(ct);
            if (sub?.InitPoint is { } ready) return Results.Ok(new SubscribeResponse(sub.Id, ready));

            if (sub is null)
            {
                sub = new Subscription { UserId = uid, ClientKey = key, Amount = plans.MonthlyPrice, CreatedAt = clock.UtcNow, UpdatedAt = clock.UtcNow };
                db.Subscriptions.Add(sub);
                try { await db.SaveChangesAsync(ct); }
                catch (DbUpdateException e) when (e.IsUniqueViolation())
                {
                    // O mesmo pedido chegou duas vezes ao mesmo tempo: o outro já está criando a assinatura.
                    db.ChangeTracker.Clear();
                    sub = await db.Subscriptions.FirstAsync(s => s.UserId == uid && s.ClientKey == key, ct);
                    if (sub.InitPoint is { } other) return Results.Ok(new SubscribeResponse(sub.Id, other));
                }
            }

            var email = await db.Users.Where(u => u.Id == uid).Select(u => u.Email).FirstAsync(ct);
            // Quem ainda tem dias de Plus (mês grátis ou período já pago de uma assinatura cancelada) só paga
            // quando eles acabam: o Mercado Pago guarda o cartão agora e faz a primeira cobrança nessa data.
            var start = new[] { plan.TrialEndsAt, plan.PaidUntil }.Max();
            object recurring = start is { } s && s > clock.UtcNow.AddHours(1)
                ? new { frequency = 1, frequency_type = "months", start_date = s.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture),
                    transaction_amount = sub.Amount, currency_id = "BRL" }
                : new { frequency = 1, frequency_type = "months", transaction_amount = sub.Amount, currency_id = "BRL" };
            MpPreapproval created;
            try
            {
                created = await mp.CreatePreapprovalAsync(new
                {
                    reason = "Economizze Plus",
                    // A referência é o id da assinatura aqui, não um dado pessoal.
                    external_reference = sub.Id.ToString(),
                    payer_email = email, // exigido pelo Mercado Pago para a cobrança
                    back_url = $"{(config["App:PublicUrl"] ?? "https://economizze.tech").TrimEnd('/')}/app/",
                    status = "pending",
                    auto_recurring = recurring,
                }, sub.CreateKey, ct);
            }
            catch (MercadoPagoRefusedException e)
            {
                log.LogWarning("Mercado Pago recusou criar a assinatura {Id}: {Reason}", sub.Id, e.Reason);
                return Results.Json(new { error = "O Mercado Pago não aceitou criar a assinatura. Tente mais tarde ou fale com o suporte." },
                    statusCode: StatusCodes.Status422UnprocessableEntity);
            }
            catch (HttpRequestException e)
            {
                log.LogWarning("Mercado Pago indisponível ao criar a assinatura {Id}: {Status}", sub.Id, e.StatusCode);
                // A chave fica gravada: tentar de novo manda a mesma ao Mercado Pago, que não cria outra assinatura.
                return Results.Json(new { error = "Não conseguimos falar com o Mercado Pago agora. Tente de novo." }, statusCode: 502);
            }
            sub.MpPreapprovalId = created.Id;
            sub.InitPoint = created.InitPoint;
            sub.Status = created.Status;
            sub.UpdatedAt = clock.UtcNow;
            await db.SaveChangesAsync(ct);
            return Results.Ok(new SubscribeResponse(sub.Id, sub.InitPoint!));
        });

        // Cancelar: o Plus continua até o fim do período já pago (PaidUntil).
        billing.MapPost("/cancel", async (ClaimsPrincipal user, AppDbContext db, MercadoPagoClient mp, AppClock clock, ILoggerFactory logs,
            CancellationToken ct) =>
        {
            var uid = user.UserId();
            var sub = await db.Subscriptions.Where(s => s.UserId == uid && s.MpPreapprovalId != null
                    && (s.Status == "authorized" || s.Status == "paused" || s.Status == "pending"))
                .OrderByDescending(s => s.CreatedAt).FirstOrDefaultAsync(ct);
            if (sub is null) return Results.NotFound(new { error = "Você não tem assinatura ativa." });
            sub.CancelKey ??= Guid.NewGuid();
            await db.SaveChangesAsync(ct); // a chave do cancelamento fica gravada antes de chamar o Mercado Pago
            try
            {
                var state = await mp.CancelPreapprovalAsync(sub.MpPreapprovalId!, sub.CancelKey.Value, ct);
                Apply(sub, state, clock);
            }
            catch (HttpRequestException e)
            {
                logs.CreateLogger("MercadoPago").LogWarning("Falha ao cancelar a assinatura {Id} no Mercado Pago: {Status} {Reason}",
                    sub.Id, e.StatusCode, (e as MercadoPagoRefusedException)?.Reason);
                return Results.Json(new { error = "Não conseguimos falar com o Mercado Pago agora. Tente de novo." }, statusCode: 502);
            }
            await db.SaveChangesAsync(ct);
            return Results.Ok(new { sub.Status, sub.PaidUntil });
        });

        app.MapPost("/api/pagamentos/webhook", HandleWebhookAsync).AllowAnonymous().WithTags("Plano");
    }

    /// <summary>
    /// Aviso do Mercado Pago. 1) Confere a assinatura (x-signature) antes de tudo. 2) Grava o id do aviso
    /// numa tabela com chave única: repetido, responde 200 e para. 3) Busca o estado atual da assinatura na
    /// API do Mercado Pago (a ordem dos avisos não importa). O id do aviso e a mudança entram na mesma
    /// transação: se a API do Mercado Pago falhar, nada fica gravado e o próximo reenvio processa de novo.
    /// </summary>
    private static async Task<IResult> HandleWebhookAsync(HttpRequest request, AppDbContext db, MercadoPagoClient mp,
        IConfiguration config, AppClock clock, ILoggerFactory logs, CancellationToken ct)
    {
        var log = logs.CreateLogger("MercadoPago");
        var secret = config["MercadoPago:WebhookSecret"];
        if (string.IsNullOrWhiteSpace(secret))
        {
            log.LogError("Webhook do Mercado Pago recusado: MercadoPago:WebhookSecret não configurado");
            return Results.StatusCode(503);
        }

        string body;
        using (var reader = new StreamReader(request.Body, Encoding.UTF8)) body = await reader.ReadToEndAsync(ct);
        string? type = request.Query["type"], dataId = request.Query["data.id"], notificationId = null;
        try
        {
            using var doc = JsonDocument.Parse(body.Length == 0 ? "{}" : body);
            var root = doc.RootElement;
            if (root.TryGetProperty("type", out var t) && t.ValueKind == JsonValueKind.String) type ??= t.GetString();
            if (root.TryGetProperty("id", out var n)) notificationId = n.ToString();
            if (dataId is null && root.TryGetProperty("data", out var d) && d.TryGetProperty("id", out var di)) dataId = di.ToString();
        }
        catch (JsonException) { return Results.BadRequest(); }

        if (!SignatureIsValid(request.Headers["x-signature"], request.Headers["x-request-id"], dataId, secret))
        {
            // Sem a chave nem o cabeçalho no log: só o que ajuda a conferir o painel (aba e aplicação certas).
            log.LogWarning("Aviso do Mercado Pago recusado: assinatura inválida (tipo {Type}, data.id {DataId})", type, dataId);
            return Results.Unauthorized();
        }
        if (string.IsNullOrEmpty(type) || string.IsNullOrEmpty(dataId)) return Results.Ok(); // aviso sem recurso: nada a fazer

        var eventKey = $"{type}:{notificationId ?? dataId}";
        await using var tx = await db.Database.BeginTransactionAsync(ct);
        db.PaymentEvents.Add(new PaymentEvent { Key = eventKey[..Math.Min(200, eventKey.Length)], Type = type, ResourceId = dataId, ReceivedAt = clock.UtcNow });
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException e) when (e.IsUniqueViolation())
        {
            return Results.Ok(); // já processado (reenvio ou cópia ao mesmo tempo): 200 e mais nada
        }

        try
        {
            var preapprovalId = type switch
            {
                "subscription_preapproval" => dataId,
                "subscription_authorized_payment" => await mp.GetAuthorizedPaymentPreapprovalIdAsync(dataId, ct),
                _ => null, // outros avisos (pagamento avulso etc.) não mudam o Plus
            };
            if (preapprovalId is not null)
            {
                var state = await mp.GetPreapprovalAsync(preapprovalId, ct);
                var sub = await db.Subscriptions.FirstOrDefaultAsync(s => s.MpPreapprovalId == state.Id, ct)
                    ?? (Guid.TryParse(state.ExternalReference, out var ours)
                        ? await db.Subscriptions.FirstOrDefaultAsync(s => s.Id == ours, ct) : null);
                if (sub is null) log.LogWarning("Assinatura {Id} do Mercado Pago sem correspondente aqui", state.Id);
                else
                {
                    sub.MpPreapprovalId ??= state.Id;
                    Apply(sub, state, clock);
                }
            }
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
            return Results.Ok();
        }
        catch (MercadoPagoRefusedException e)
        {
            // O recurso do aviso não existe (ex.: o "testar URL" do painel manda o id 123456): não há o que
            // atualizar e repetir não muda isso. 200 e o aviso marcado, senão o Mercado Pago reenviaria para sempre.
            log.LogWarning("Aviso {Key} do Mercado Pago ignorado: {Reason}", eventKey, e.Reason);
            await tx.CommitAsync(ct);
            return Results.Ok();
        }
        catch (HttpRequestException e)
        {
            // Rollback: o id do aviso não fica gravado e o Mercado Pago reenvia.
            log.LogWarning(e, "Mercado Pago indisponível ao processar o aviso {Key}", eventKey);
            return Results.StatusCode(503);
        }
    }

    /// <summary>
    /// Rede de segurança do webhook: se um aviso se perdeu, a assinatura ficaria "pending" mesmo paga. Ao
    /// abrir o plano, as assinaturas ainda não confirmadas da última semana são conferidas no Mercado Pago,
    /// no máximo uma vez a cada 15 segundos cada (UpdatedAt). Falha aqui não impede de mostrar o plano.
    /// </summary>
    private static async Task SyncPendingAsync(Guid userId, AppDbContext db, MercadoPagoClient mp, AppClock clock, ILogger log,
        CancellationToken ct)
    {
        if (!mp.IsConfigured) return;
        var now = clock.UtcNow;
        var (since, calm) = (now.AddDays(-7), now.AddSeconds(-15));
        var pending = await db.Subscriptions
            .Where(s => s.UserId == userId && s.Status == "pending" && s.MpPreapprovalId != null && s.CreatedAt > since && s.UpdatedAt < calm)
            .ToListAsync(ct);
        foreach (var sub in pending)
        {
            try { Apply(sub, await mp.GetPreapprovalAsync(sub.MpPreapprovalId!, ct), clock); }
            catch (HttpRequestException e)
            {
                sub.UpdatedAt = now; // espera os 15 segundos antes de perguntar de novo
                log.LogWarning("Não deu para conferir a assinatura {Id} no Mercado Pago: {Status} {Reason}",
                    sub.Id, e.StatusCode, (e as MercadoPagoRefusedException)?.Reason);
            }
        }
        if (pending.Count > 0) await db.SaveChangesAsync(ct);
    }

    /// <summary>Estado vindo da API do Mercado Pago. Ativa: o Plus vale ao menos até a próxima cobrança.</summary>
    private static void Apply(Subscription sub, MpPreapproval state, AppClock clock)
    {
        sub.Status = state.Status;
        sub.NextPaymentDate = state.NextPaymentDate?.ToUniversalTime();
        if (state.Status == "authorized" && sub.NextPaymentDate is { } next && (sub.PaidUntil is null || next > sub.PaidUntil))
            sub.PaidUntil = next;
        sub.UpdatedAt = clock.UtcNow;
    }

    /// <summary>
    /// x-signature do Mercado Pago: "ts=...,v1=...". v1 é o HMAC-SHA256 (hex) de
    /// "id:{data.id};request-id:{x-request-id};ts:{ts};" com a chave secreta do painel. Comparação em tempo constante.
    /// </summary>
    public static bool SignatureIsValid(string? header, string? requestId, string? dataId, string secret)
    {
        if (string.IsNullOrEmpty(header)) return false;
        string? ts = null, v1 = null;
        foreach (var part in header.Split(','))
        {
            var kv = part.Split('=', 2, StringSplitOptions.TrimEntries);
            if (kv.Length != 2) continue;
            if (kv[0] == "ts") ts = kv[1];
            else if (kv[0] == "v1") v1 = kv[1];
        }
        if (ts is null || v1 is null) return false;
        var manifest = new StringBuilder();
        // Partes ausentes ficam fora do texto assinado, como nos exemplos do Mercado Pago. O id alfanumérico vai em minúsculas.
        if (!string.IsNullOrEmpty(dataId)) manifest.Append($"id:{dataId.ToLowerInvariant()};");
        if (!string.IsNullOrEmpty(requestId)) manifest.Append($"request-id:{requestId};");
        manifest.Append($"ts:{ts};");
        var expected = Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes(manifest.ToString())))
            .ToLowerInvariant();
        return CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(expected), Encoding.ASCII.GetBytes(v1.ToLowerInvariant()));
    }
}
