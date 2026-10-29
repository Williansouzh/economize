using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Financas.Api.Data;

/// <summary>Erros do PostgreSQL que viram resposta para o usuário (em vez de 500).</summary>
public static class DbErrors
{
    /// <summary>Violação de índice único. Com <paramref name="index"/>, só a desse índice.</summary>
    public static bool IsUniqueViolation(this DbUpdateException e, string? index = null) =>
        e.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation } pg
        && (index is null || pg.ConstraintName == index);

    public const string CategoryName = "IX_Categories_UserId_Type_LowerName";
    public const string ImportedLine = "IX_Transactions_AccountId_ExternalId";
    public const string LinkCode = "IX_Users_WhatsAppLinkCode";
}
