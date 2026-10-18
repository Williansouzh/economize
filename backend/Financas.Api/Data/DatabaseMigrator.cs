using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage;
using Npgsql;

namespace Financas.Api.Data;

/// <summary>
/// Aplica as migrations pendentes com segurança quando várias réplicas sobem ao mesmo tempo.
/// O lock do próprio EF Core não basta: com duas ou mais migrations pendentes, as réplicas leem a
/// mesma lista e a segunda tenta aplicar de novo ("column already exists"). Aqui um advisory lock
/// do PostgreSQL serializa tudo, e quem entra depois já não encontra nada pendente.
/// </summary>
public static class DatabaseMigrator
{
    private const long LockKey = 7_262_001;

    public static void Migrate(AppDbContext db)
    {
        // O advisory lock vale por banco, então o banco precisa existir antes de travar.
        var creator = db.GetService<IRelationalDatabaseCreator>();
        if (!creator.Exists())
        {
            try { creator.Create(); }
            catch (PostgresException e) when (e.SqlState == PostgresErrorCodes.DuplicateDatabase) { }
        }

        db.Database.OpenConnection();
        try
        {
            db.Database.ExecuteSqlRaw($"SELECT pg_advisory_lock({LockKey})");
            db.Database.Migrate();
        }
        finally
        {
            db.Database.ExecuteSqlRaw($"SELECT pg_advisory_unlock({LockKey})");
            db.Database.CloseConnection();
        }
    }
}
