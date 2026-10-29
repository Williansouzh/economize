using System.Text.RegularExpressions;

namespace Financas.Api.Services;

/// <summary>
/// RN-50: o token que o agente do WhatsApp recebe em /api/agent/token só vale nas rotas que o assistente usa.
/// Assim, quem tiver a chave do agente não consegue excluir contas, desvincular números, encerrar
/// sessões, exportar dados, renovar o token por 14 dias nem abrir o painel do admin.
/// </summary>
public static partial class AgentTokenScope
{
    /// <summary>Método e rota liberados (as chamadas de agent/app/finance_api.py).</summary>
    private static readonly (string Method, Regex Path)[] Allowed =
    [
        ("GET", Route("/api/categories")),
        ("GET", Route("/api/accounts")),
        ("GET", Route("/api/profiles")),
        ("GET", Route("/api/dashboard")),
        ("GET", Route("/api/transactions")),
        ("POST", Route("/api/transactions")),
        ("DELETE", Route("/api/transactions/{id}")),
        ("POST", Route("/api/insights/quota/whatsapp")),
    ];

    public static bool IsAllowed(string method, string path) =>
        Allowed.Any(a => a.Method == method && a.Path.IsMatch(path));

    public static IApplicationBuilder UseAgentTokenScope(this IApplicationBuilder app) => app.Use(async (ctx, next) =>
    {
        if (ctx.User.FindFirst(TokenService.ViaClaim)?.Value == TokenService.ViaAgent
            && !IsAllowed(ctx.Request.Method, ctx.Request.Path.Value ?? ""))
        {
            await Results.Json(new { error = "O assistente do WhatsApp não pode usar esta rota." },
                statusCode: StatusCodes.Status403Forbidden).ExecuteAsync(ctx);
            return;
        }
        await next();
    });

    // "{id}" aceita um Guid; a barra no fim é opcional.
    private static Regex Route(string template) => new(
        "^" + Regex.Escape(template).Replace(@"\{id}", "[0-9a-fA-F-]{36}") + "/?$", RegexOptions.CultureInvariant);
}
