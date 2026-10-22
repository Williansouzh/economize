using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage;
using Npgsql;

namespace Financas.Api.Data;

/// <summary>
/// Aplica as migrations pendentes com um advisory lock do PostgreSQL segurado durante todo o processo.
/// O lock do próprio EF Core vale por transação e é solto entre uma migration e a próxima; com duas
/// réplicas subindo juntas, a segunda chegava a reaplicar uma migration que a primeira já tinha aplicado.
/// </summary>
public static class DatabaseMigrator
{
    // Número arbitrário e fixo que identifica "migrations da API Finanças" no servidor.
    private const long LockId = 7_202_610_170_001;

    public static void MigrateWithLock(AppDbContext db)
    {
        EnsureDatabaseExists(db);

        // Conexão separada, aberta do começo ao fim: o lock é da sessão.
        using var conn = new NpgsqlConnection(db.Database.GetConnectionString());
        conn.Open();
        using (var take = new NpgsqlCommand($"SELECT pg_advisory_lock({LockId})", conn)) take.ExecuteNonQuery();
        try
        {
            // Lê as migrations aplicadas só depois de ter o lock: quem esperou vê o que a outra réplica fez.
            db.Database.Migrate();
        }
        finally
        {
            using var release = new NpgsqlCommand($"SELECT pg_advisory_unlock({LockId})", conn);
            release.ExecuteNonQuery();
        }
    }

    /// <summary>Cria o banco vazio se ainda não existir (o lock precisa de um banco para conectar).</summary>
    private static void EnsureDatabaseExists(AppDbContext db)
    {
        var creator = db.GetService<IRelationalDatabaseCreator>();
        if (creator.Exists()) return;
        try
        {
            creator.Create();
        }
        catch (PostgresException e) when (e.SqlState == PostgresErrorCodes.DuplicateDatabase)
        {
            // Outra réplica criou no mesmo instante.
        }
    }
}
