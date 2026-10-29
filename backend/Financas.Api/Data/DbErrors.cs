using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace Financas.Api.Data;

/// <summary>Erros do PostgreSQL que viram resposta para o usuário (em vez de 500).</summary>
public static class DbErrors
{
    /// <summary>Violação de índice único. Com <paramref name="index"/>, só a desse índice.</summary>
    public static bool IsUniqueViolation(this DbUpdateException e, string? index = null) =>
        Is(e.InnerException, PostgresErrorCodes.UniqueViolation, index);

    /// <summary>O mesmo para ExecuteUpdate/ExecuteDelete e SQL direto, que lançam a PostgresException sem embrulho.</summary>
    public static bool IsUniqueViolation(this Exception e, string? index = null) =>
        Is(e, PostgresErrorCodes.UniqueViolation, index) || Is(e.InnerException, PostgresErrorCodes.UniqueViolation, index);

    /// <summary>Chave estrangeira: o registro apontado sumiu no meio (ou ainda é usado por outro).</summary>
    public static bool IsForeignKeyViolation(this Exception e) =>
        Is(e, PostgresErrorCodes.ForeignKeyViolation, null) || Is(e.InnerException, PostgresErrorCodes.ForeignKeyViolation, null);

    private static bool Is(Exception? e, string state, string? index) =>
        e is PostgresException pg && pg.SqlState == state && (index is null || pg.ConstraintName == index);

    public const string CategoryName = "IX_Categories_UserId_Type_LowerName";
    public const string ImportedLine = "IX_Transactions_AccountId_ExternalId";
    public const string LinkCode = "IX_Users_WhatsAppLinkCode";
}
