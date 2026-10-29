using System.Text.RegularExpressions;

namespace Financas.Api.Services;

/// <summary>
/// Cor e ícone de contas, categorias e metas. Sem esse limite, a API aceitava textos de vários MB
/// nesses campos (e, onde o banco já tinha limite, respondia 500 em vez de 400).
/// </summary>
public static partial class Appearance
{
    public const int MaxColorLength = 9;  // #RRGGBB ou #RRGGBBAA
    public const int MaxIconLength = 40;  // nome de ícone do Material (ex.: inventory_2)

    /// <summary>null = não mudar (o campo é opcional nos pedidos).</summary>
    public static IResult? Validate(string? color, string? icon)
    {
        if (color is not null && !ColorPattern().IsMatch(color))
            return Results.BadRequest(new { error = "Cor inválida. Use o formato #RRGGBB." });
        if (icon is not null && !IconPattern().IsMatch(icon))
            return Results.BadRequest(new { error = "Ícone inválido." });
        return null;
    }

    [GeneratedRegex("^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$")]
    private static partial Regex ColorPattern();

    [GeneratedRegex("^[a-z0-9_]{1,40}$")]
    private static partial Regex IconPattern();
}
