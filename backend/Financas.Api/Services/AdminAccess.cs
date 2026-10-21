namespace Financas.Api.Services;

/// <summary>
/// Super admin (RN-44): e-mails em Admin:Emails, separados por vírgula (ADMIN_EMAILS no .env do servidor).
/// Ficam fora do repositório, que é público.
/// </summary>
public class AdminAccess(IConfiguration config)
{
    private readonly HashSet<string> _emails = (config["Admin:Emails"] ?? "")
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .ToHashSet(StringComparer.OrdinalIgnoreCase);

    public bool IsAdmin(string? email) => email is not null && _emails.Contains(email.Trim());
}
