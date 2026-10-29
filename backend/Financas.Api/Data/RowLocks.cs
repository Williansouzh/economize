using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;

namespace Financas.Api.Data;

/// <summary>Locks de linha do PostgreSQL (SELECT ... FOR UPDATE), sempre dentro de uma transação.</summary>
public static class RowLocks
{
    /// <summary>
    /// Trava a linha do usuário até o fim da transação: pedidos do mesmo usuário que mexem em várias
    /// tabelas de uma vez (criar perfil com limite, começar do zero) passam um de cada vez.
    /// Devolve false se o usuário não existe mais.
    /// </summary>
    public static async Task<bool> LockUserAsync(this DatabaseFacade db, Guid userId) =>
        (await db.SqlQuery<int>($"""SELECT 1 AS "Value" FROM "Users" WHERE "Id" = {userId} FOR UPDATE""").ToListAsync()).Count > 0;
}
