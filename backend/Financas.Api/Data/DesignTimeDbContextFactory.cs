using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace Financas.Api.Data;

/// <summary>Usado só pelo "dotnet ef" para gerar migrations, sem subir a API inteira.</summary>
public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args) => new(new DbContextOptionsBuilder<AppDbContext>()
        .UseNpgsql(Environment.GetEnvironmentVariable("ConnectionStrings__Default")
                   ?? "Host=localhost;Database=financas;Username=postgres")
        .Options);
}
