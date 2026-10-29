using System.Security.Claims;
using Financas.Api.Dtos;
using Financas.Api.Services;

namespace Financas.Api.Endpoints;

/// <summary>Importação de extratos (RN-42) e dos gastos detectados nas notificações do banco (RN-43).
/// Fluxo: parse (arquivo → linhas) → preview (categoria e repetidos) → commit (o que o usuário confirmou).</summary>
public static class ImportEndpoints
{
    public static void MapImportEndpoints(this IEndpointRouteBuilder app)
    {
        var g = app.MapGroup("/api/import").RequireAuthorization().WithTags("Importação");

        g.MapPost("/parse", async (ImportParseRequest req, ClaimsPrincipal user, ImportService import, CancellationToken ct) =>
        {
            byte[] content;
            try { content = Convert.FromBase64String(req.Content ?? ""); }
            catch (FormatException) { return Results.BadRequest(new { error = "Arquivo inválido." }); }
            if (content.Length == 0) return Results.BadRequest(new { error = "O arquivo está vazio." });
            if (content.Length > ImportService.MaxFileBytes)
                return Results.BadRequest(new { error = "O arquivo pode ter no máximo 5 MB." });
            return await Run(async () => Results.Ok(new { items = await import.ParseAsync(user.UserId(), req.FileName ?? "", content, ct) }));
        });

        g.MapPost("/preview", async (ImportPreviewRequest req, ClaimsPrincipal user, ImportService import, CancellationToken ct) =>
        {
            if (req.Items.Count > StatementLimits) return Results.BadRequest(new { error = $"Envie no máximo {StatementLimits} linhas." });
            return Results.Ok(await import.PreviewAsync(user.ProfileId(), req.AccountId, req.Items, ct));
        });

        g.MapPost("/commit", async (ImportCommitRequest req, ClaimsPrincipal user, ImportService import, CancellationToken ct) =>
            await Run(async () => Results.Ok(new { created = await import.CommitAsync(user.ProfileId(), req, ct) })));
    }

    private const int StatementLimits = StatementParser.MaxLines;

    private static async Task<IResult> Run(Func<Task<IResult>> action)
    {
        try { return await action(); }
        catch (ImportService.ImportException e) { return Results.Json(new { error = e.Message }, statusCode: e.Status); }
    }
}
