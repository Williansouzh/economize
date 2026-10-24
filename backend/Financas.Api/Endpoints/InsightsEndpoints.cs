using System.Security.Claims;
using Financas.Api.Dtos;
using Financas.Api.Services;

namespace Financas.Api.Endpoints;

public static class InsightsEndpoints
{
    public static void MapInsightsEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/insights").RequireAuthorization().WithTags("IA (DeepSeek)");

        g.MapPost("/", async (InsightsRequest req, ClaimsPrincipal user, InsightsService insights,
            DeepSeekClient deepSeek, AiQuota quota, CancellationToken ct) =>
        {
            if (!deepSeek.IsConfigured) return NotConfigured();
            var uid = user.UserId();
            var consumed = false;
            try
            {
                var result = await insights.GetInsightsAsync(uid, user.ProfileId(), req.Month, req.IncludeDescriptions,
                    async () => consumed = await quota.TryUseAsync(uid, AiQuota.Insights, ct) is not null, ct);
                return result is null
                    ? QuotaExceeded($"Você já gerou {quota.Limit(AiQuota.Insights)} análises hoje. Amanhã tem mais!", quota)
                    : Results.Ok(result);
            }
            catch (HttpRequestException)
            {
                if (consumed) await quota.RefundAsync(uid, AiQuota.Insights);
                return Unavailable();
            }
        });

        g.MapGet("/quota", async (ClaimsPrincipal user, AiQuota quota) =>
        {
            var used = await quota.UsedAsync(user.UserId(), AiQuota.Chat);
            var limit = quota.Limit(AiQuota.Chat);
            return new AiQuotaDto(used, limit, Math.Max(0, limit - used), quota.ResetsAt);
        });

        // O agente do WhatsApp gasta uma mensagem da cota antes de chamar a IA (RN-48).
        g.MapPost("/quota/whatsapp", async (ClaimsPrincipal user, AiQuota quota, CancellationToken ct) =>
            await quota.TryUseAsync(user.UserId(), AiQuota.WhatsApp, ct) is { } remaining
                ? Results.Ok(new { remaining })
                : QuotaExceeded("Limite de mensagens do dia atingido.", quota));

        g.MapPost("/chat", async (ChatRequest req, ClaimsPrincipal user, InsightsService insights,
            DeepSeekClient deepSeek, AiQuota quota, CancellationToken ct) =>
        {
            if (!deepSeek.IsConfigured) return NotConfigured();
            var question = (req.Question ?? "").Trim();
            if (question.Length == 0) return Results.BadRequest(new { error = "Pergunta vazia." });
            if (question.Length > InsightsService.MaxQuestionLength)
                return Results.BadRequest(new { error = $"Pergunte com até {InsightsService.MaxQuestionLength} caracteres." });

            var uid = user.UserId();
            if (await quota.TryUseAsync(uid, AiQuota.Chat, ct) is not { } remaining)
                return QuotaExceeded($"Suas {quota.Limit(AiQuota.Chat)} perguntas de hoje acabaram. Amanhã a gente continua! 😊", quota);
            try
            {
                var answer = await insights.AskAsync(uid, user.ProfileId(), question, req.Month, req.IncludeDescriptions, ct);
                return Results.Ok(new ChatResponse(answer, remaining));
            }
            catch (HttpRequestException)
            {
                await quota.RefundAsync(uid, AiQuota.Chat);
                return Unavailable();
            }
        });
    }

    private static IResult NotConfigured() => Results.Problem(
        "Configure a chave DeepSeek:ApiKey no backend.", statusCode: StatusCodes.Status503ServiceUnavailable);

    private static IResult Unavailable() => Results.Problem(
        "Não foi possível falar com a IA agora. Tente novamente.", statusCode: StatusCodes.Status502BadGateway);

    private static IResult QuotaExceeded(string message, AiQuota quota) =>
        Results.Json(new { error = message, resetsAt = quota.ResetsAt }, statusCode: StatusCodes.Status429TooManyRequests);
}
