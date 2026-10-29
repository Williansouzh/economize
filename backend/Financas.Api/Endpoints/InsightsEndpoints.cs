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
                if (result is not null) return Results.Ok(result);
                var (limit, _, plus) = await quota.RuleAsync(uid, AiQuota.Insights);
                return QuotaExceeded(plus
                    ? $"Você já gerou {limit} análises hoje. Amanhã tem mais!"
                    : "Você já usou a análise grátis desta semana. Com o Plus são 10 por dia.", quota, !plus);
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
            var limit = await quota.LimitAsync(user.UserId(), AiQuota.Chat);
            return new AiQuotaDto(used, limit, Math.Max(0, limit - used), quota.ResetsAt);
        });

        // O agente do WhatsApp gasta uma mensagem da cota antes de chamar a IA (RN-48).
        // O assistente do WhatsApp é do Plus (RN-51): sem ele, 403 com a explicação, que o agente repassa.
        g.MapPost("/quota/whatsapp", async (ClaimsPrincipal user, AiQuota quota, PlanService plans, CancellationToken ct) =>
        {
            if (!await plans.IsPlusAsync(user.UserId())) return PlanService.PlusRequired("O assistente no WhatsApp");
            return await quota.TryUseAsync(user.UserId(), AiQuota.WhatsApp, ct) is { } remaining
                ? Results.Ok(new { remaining })
                : QuotaExceeded("Limite de mensagens do dia atingido.", quota);
        });

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
            {
                var (limit, _, plus) = await quota.RuleAsync(uid, AiQuota.Chat);
                return QuotaExceeded(plus
                    ? $"Suas {limit} perguntas de hoje acabaram. Amanhã a gente continua! 😊"
                    : $"Suas {limit} perguntas grátis de hoje acabaram. Com o Plus são 20 por dia.", quota, !plus);
            }
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

    private static IResult QuotaExceeded(string message, AiQuota quota, bool plusUnlocks = false) =>
        Results.Json(new { error = message, resetsAt = quota.ResetsAt, plusRequired = plusUnlocks },
            statusCode: StatusCodes.Status429TooManyRequests);
}
