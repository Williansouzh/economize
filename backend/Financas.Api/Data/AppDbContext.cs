using Financas.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<UserActivity> UserActivity => Set<UserActivity>();
    public DbSet<Account> Accounts => Set<Account>();
    public DbSet<Transfer> Transfers => Set<Transfer>();
    public DbSet<Category> Categories => Set<Category>();
    public DbSet<Transaction> Transactions => Set<Transaction>();
    public DbSet<Budget> Budgets => Set<Budget>();
    public DbSet<LinkAttempt> LinkAttempts => Set<LinkAttempt>();
    public DbSet<RateLimitCounter> RateLimitCounters => Set<RateLimitCounter>();
    public DbSet<Goal> Goals => Set<Goal>();
    public DbSet<Profile> Profiles => Set<Profile>();
    public DbSet<AiUsage> AiUsage => Set<AiUsage>();
    public DbSet<AiCache> AiCache => Set<AiCache>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<User>().HasIndex(u => u.Email).IsUnique();
        b.Entity<User>().HasIndex(u => u.WhatsAppPhone).IsUnique();
        b.Entity<Transaction>().HasIndex(t => new { t.UserId, t.Date });
        b.Entity<Budget>().HasIndex(x => new { x.UserId, x.CategoryId, x.Month }).IsUnique();

        b.Entity<Transaction>().HasOne(t => t.Account).WithMany().OnDelete(DeleteBehavior.Cascade);
        b.Entity<Transaction>().HasOne(t => t.Category).WithMany().OnDelete(DeleteBehavior.Restrict);
        // RN-06: excluir uma conta exclui também as transferências de e para ela.
        b.Entity<Transfer>().HasOne(t => t.FromAccount).WithMany().HasForeignKey(t => t.FromAccountId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<Transfer>().HasOne(t => t.ToAccount).WithMany().HasForeignKey(t => t.ToAccountId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<Transfer>().HasIndex(t => new { t.UserId, t.Date });
        b.Entity<Transaction>().HasIndex(t => t.SeriesId);
        b.Entity<Transaction>().HasIndex(t => new { t.AccountId, t.ExternalId });
        b.Entity<Transaction>().Property(t => t.ExternalId).HasMaxLength(100);
        b.Entity<Transaction>().Property(t => t.IdempotencyKey).HasMaxLength(100);
        b.Entity<Transaction>().HasIndex(t => new { t.UserId, t.IdempotencyKey }).IsUnique()
            .HasFilter("\"IdempotencyKey\" IS NOT NULL");
        b.Entity<Goal>().HasIndex(g => g.UserId);

        // Dinheiro: numeric(14,2) — até R$ 999 bilhões, sempre com 2 casas.
        b.Entity<Transaction>().Property(t => t.Amount).HasPrecision(14, 2);
        b.Entity<Account>().Property(a => a.InitialBalance).HasPrecision(14, 2);
        b.Entity<Budget>().Property(x => x.Limit).HasPrecision(14, 2);
        b.Entity<Transfer>().Property(t => t.Amount).HasPrecision(14, 2);
        b.Entity<Account>().Property(a => a.CreditLimit).HasPrecision(14, 2);
        b.Entity<Goal>().Property(g => g.Target).HasPrecision(14, 2);
        b.Entity<Goal>().Property(g => g.Saved).HasPrecision(14, 2);
        b.Entity<Goal>().Property(g => g.Name).HasMaxLength(60);
        b.Entity<Goal>().Property(g => g.Icon).HasMaxLength(40);
        b.Entity<Goal>().Property(g => g.Color).HasMaxLength(9);
        b.Entity<User>().Property(u => u.ResetCodeHash).HasMaxLength(64);
        // Lançamentos que já existiam ganham "agora" como data de registro.
        b.Entity<Transaction>().Property(t => t.CreatedAt).HasDefaultValueSql("now()");

        b.Entity<User>().Property(u => u.Email).HasMaxLength(254);
        b.Entity<User>().Property(u => u.WhatsAppPhone).HasMaxLength(20);
        b.Entity<User>().Property(u => u.WhatsAppLinkCode).HasMaxLength(6);
        b.Entity<Budget>().Property(x => x.Month).HasMaxLength(7);
        b.Entity<Budget>().Property(x => x.UntilMonth).HasMaxLength(7);
        b.Entity<Transfer>().Property(t => t.Description).HasMaxLength(200);
        b.Entity<Transaction>().Property(t => t.Description).HasMaxLength(200);
        b.Entity<Account>().Property(a => a.Icon).HasMaxLength(40);

        b.Entity<UserActivity>().HasKey(x => new { x.UserId, x.Day });
        b.Entity<UserActivity>().HasIndex(x => x.Day);
        b.Entity<UserActivity>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);

        b.Entity<LinkAttempt>().HasKey(x => x.Phone);
        b.Entity<LinkAttempt>().Property(x => x.Phone).HasMaxLength(20);

        b.Entity<RateLimitCounter>().HasKey(x => new { x.Key, x.WindowStart });
        b.Entity<RateLimitCounter>().Property(x => x.Key).HasMaxLength(120);

        b.Entity<User>().Property(u => u.State).HasMaxLength(2);
        b.Entity<User>().Property(u => u.IncomeSources).HasMaxLength(200);
        b.Entity<User>().Property(u => u.MainGoal).HasMaxLength(30);
        b.Entity<User>().Property(u => u.DeclaredIncome).HasPrecision(14, 2);

        b.Entity<Profile>().HasIndex(p => p.OwnerId);
        b.Entity<Profile>().Property(p => p.Name).HasMaxLength(60);
        b.Entity<Profile>().Property(p => p.Cnpj).HasMaxLength(14);
        b.Entity<Profile>().HasOne<User>().WithMany().HasForeignKey(p => p.OwnerId).OnDelete(DeleteBehavior.Cascade);

        b.Entity<AiUsage>().HasKey(x => new { x.UserId, x.Day, x.Kind });
        b.Entity<AiUsage>().Property(x => x.Kind).HasMaxLength(20);
        b.Entity<AiUsage>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Cascade);

        b.Entity<AiCache>().HasKey(x => new { x.ProfileId, x.Key });
        b.Entity<AiCache>().Property(x => x.Key).HasMaxLength(60);
        b.Entity<AiCache>().Property(x => x.ContextHash).HasMaxLength(64);
    }

    /// <summary>Categorias padrão criadas no cadastro do usuário (estilo Organizze).</summary>
    public static IEnumerable<Category> DefaultCategories(Guid userId) =>
    [
        new() { UserId = userId, Name = "Alimentação", Type = TransactionType.Expense, Icon = "restaurant", Color = "#B55E43" },
        new() { UserId = userId, Name = "Moradia", Type = TransactionType.Expense, Icon = "home", Color = "#A86B16" },
        new() { UserId = userId, Name = "Transporte", Type = TransactionType.Expense, Icon = "directions_car", Color = "#3080BC" },
        new() { UserId = userId, Name = "Saúde", Type = TransactionType.Expense, Icon = "local_hospital", Color = "#008E96" },
        new() { UserId = userId, Name = "Educação", Type = TransactionType.Expense, Icon = "school", Color = "#6673C1" },
        new() { UserId = userId, Name = "Lazer", Type = TransactionType.Expense, Icon = "celebration", Color = "#8B66B3" },
        new() { UserId = userId, Name = "Compras", Type = TransactionType.Expense, Icon = "shopping_bag", Color = "#A85C90" },
        new() { UserId = userId, Name = "Assinaturas", Type = TransactionType.Expense, Icon = "subscriptions", Color = "#607089" },
        new() { UserId = userId, Name = "Outros", Type = TransactionType.Expense, Icon = "more_horiz", Color = "#668E93" },
        new() { UserId = userId, Name = "Salário", Type = TransactionType.Income, Icon = "payments", Color = "#728426" },
        new() { UserId = userId, Name = "Freelance", Type = TransactionType.Income, Icon = "work", Color = "#008E96" },
        new() { UserId = userId, Name = "Investimentos", Type = TransactionType.Income, Icon = "trending_up", Color = "#3080BC" },
        new() { UserId = userId, Name = "Outras receitas", Type = TransactionType.Income, Icon = "attach_money", Color = "#668E93" },
    ];

    /// <summary>Categorias de um perfil de empresa (RN-47). "Pró-labore" é o que vai da empresa para a pessoa.</summary>
    public static IEnumerable<Category> BusinessCategories(Guid profileId) =>
    [
        new() { UserId = profileId, Name = "DAS (imposto do MEI)", Type = TransactionType.Expense, Icon = "receipt_long", Color = "#607089" },
        new() { UserId = profileId, Name = "Mercadorias e fornecedores", Type = TransactionType.Expense, Icon = "inventory_2", Color = "#A86B16" },
        new() { UserId = profileId, Name = "Pró-labore", Type = TransactionType.Expense, Icon = "person", Color = "#008E96" },
        new() { UserId = profileId, Name = "Ferramentas e software", Type = TransactionType.Expense, Icon = "build", Color = "#6673C1" },
        new() { UserId = profileId, Name = "Marketing", Type = TransactionType.Expense, Icon = "campaign", Color = "#A85C90" },
        new() { UserId = profileId, Name = "Taxas e maquininha", Type = TransactionType.Expense, Icon = "credit_card", Color = "#8B66B3" },
        new() { UserId = profileId, Name = "Transporte e entregas", Type = TransactionType.Expense, Icon = "local_shipping", Color = "#3080BC" },
        new() { UserId = profileId, Name = "Outras despesas", Type = TransactionType.Expense, Icon = "more_horiz", Color = "#668E93" },
        new() { UserId = profileId, Name = "Vendas", Type = TransactionType.Income, Icon = "storefront", Color = "#728426" },
        new() { UserId = profileId, Name = "Serviços prestados", Type = TransactionType.Income, Icon = "handyman", Color = "#008E96" },
        new() { UserId = profileId, Name = "Outras receitas", Type = TransactionType.Income, Icon = "attach_money", Color = "#668E93" },
    ];
}
