using Financas.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Account> Accounts => Set<Account>();
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<Transaction> Transactions => Set<Transaction>();
    public DbSet<Budget> Budgets => Set<Budget>();
    public DbSet<LinkAttempt> LinkAttempts => Set<LinkAttempt>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>().HasIndex(u => u.Email).IsUnique();
        b.Entity<User>().HasIndex(u => u.WhatsAppPhone).IsUnique();
        b.Entity<Transaction>().HasIndex(t => new { t.UserId, t.Date });
        b.Entity<Budget>().HasIndex(x => new { x.UserId, x.CategoryId, x.Month }).IsUnique();

        b.Entity<Transaction>().HasOne(t => t.Account).WithMany().OnDelete(DeleteBehavior.Cascade);
        b.Entity<Transaction>().HasOne(t => t.Category).WithMany().OnDelete(DeleteBehavior.Restrict);

        // Dinheiro: numeric(14,2) — até R$ 999 bilhões, sempre com 2 casas.
        b.Entity<Transaction>().Property(t => t.Amount).HasPrecision(14, 2);
        b.Entity<Account>().Property(a => a.InitialBalance).HasPrecision(14, 2);
        b.Entity<Budget>().Property(x => x.Limit).HasPrecision(14, 2);

        b.Entity<User>().Property(u => u.Email).HasMaxLength(254);
        b.Entity<User>().Property(u => u.WhatsAppPhone).HasMaxLength(20);
        b.Entity<User>().Property(u => u.WhatsAppLinkCode).HasMaxLength(6);
        b.Entity<Budget>().Property(x => x.Month).HasMaxLength(7);
        b.Entity<Transaction>().Property(t => t.Description).HasMaxLength(200);
        b.Entity<Account>().Property(a => a.Icon).HasMaxLength(40);

        b.Entity<LinkAttempt>().HasKey(x => x.Phone);
        b.Entity<LinkAttempt>().Property(x => x.Phone).HasMaxLength(20);
    }

    /// <summary>Categorias padrão criadas no cadastro do usuário (estilo Organizze).</summary>
    public static IEnumerable<Category> DefaultCategories(Guid userId) =>
    [
        new() { UserId = userId, Name = "Alimentação", Type = TransactionType.Expense, Icon = "restaurant", Color = "#F44336" },
        new() { UserId = userId, Name = "Moradia", Type = TransactionType.Expense, Icon = "home", Color = "#795548" },
        new() { UserId = userId, Name = "Transporte", Type = TransactionType.Expense, Icon = "directions_car", Color = "#2196F3" },
        new() { UserId = userId, Name = "Saúde", Type = TransactionType.Expense, Icon = "local_hospital", Color = "#E91E63" },
        new() { UserId = userId, Name = "Educação", Type = TransactionType.Expense, Icon = "school", Color = "#3F51B5" },
        new() { UserId = userId, Name = "Lazer", Type = TransactionType.Expense, Icon = "celebration", Color = "#FF9800" },
        new() { UserId = userId, Name = "Compras", Type = TransactionType.Expense, Icon = "shopping_bag", Color = "#9C27B0" },
        new() { UserId = userId, Name = "Assinaturas", Type = TransactionType.Expense, Icon = "subscriptions", Color = "#607D8B" },
        new() { UserId = userId, Name = "Outros", Type = TransactionType.Expense, Icon = "more_horiz", Color = "#9E9E9E" },
        new() { UserId = userId, Name = "Salário", Type = TransactionType.Income, Icon = "payments", Color = "#4CAF50" },
        new() { UserId = userId, Name = "Freelance", Type = TransactionType.Income, Icon = "work", Color = "#009688" },
        new() { UserId = userId, Name = "Investimentos", Type = TransactionType.Income, Icon = "trending_up", Color = "#8BC34A" },
        new() { UserId = userId, Name = "Outras receitas", Type = TransactionType.Income, Icon = "attach_money", Color = "#CDDC39" },
    ];
}
