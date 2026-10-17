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
            DeepSeekClient deepSeek, CancellationToken ct) =>
        {
            if (!deepSeek.IsConfigured) return NotConfigured();
            try { return Results.Ok(await insights.GetInsightsAsync(user.UserId(), req.Month, ct)); }
            catch (HttpRequestException) { return Unavailable(); }
        });

        g.MapPost("/chat", async (ChatRequest req, ClaimsPrincipal user, InsightsService insights,
            DeepSeekClient deepSeek, CancellationToken ct) =>
        {
            if (!deepSeek.IsConfigured) return NotConfigured();
            if (string.IsNullOrWhiteSpace(req.Question)) return Results.BadRequest(new { error = "Pergunta vazia." });
            try { return Results.Ok(new ChatResponse(await insights.AskAsync(user.UserId(), req.Question, req.Month, ct))); }
            catch (HttpRequestException) { return Unavailable(); }
        });
    }

    private static IResult NotConfigured() => Results.Problem(
        "Configure a chave DeepSeek:ApiKey no backend.", statusCode: StatusCodes.Status503ServiceUnavailable);

    private static IResult Unavailable() => Results.Problem(
        "Não foi possível falar com a IA agora. Tente novamente.", statusCode: StatusCodes.Status502BadGateway);
}
