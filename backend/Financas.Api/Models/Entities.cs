namespace Financas.Api.Models;

public enum TransactionType { Income = 1, Expense = 2 }

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Email { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>Número do WhatsApp vinculado (formato wa_id, ex.: 5511999999999).</summary>
    public string? WhatsAppPhone { get; set; }
    /// <summary>Código temporário que o usuário envia ao bot para provar que é dono do número.</summary>
    public string? WhatsAppLinkCode { get; set; }
    public DateTime? WhatsAppLinkCodeExpiresAt { get; set; }
}

/// <summary>Conta bancária, carteira, poupança etc.</summary>
public class Account
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Name { get; set; } = "";
    public decimal InitialBalance { get; set; }
    public string Color { get; set; } = "#4CAF50";
    public string Icon { get; set; } = "account_balance_wallet";
}

public class Category
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Name { get; set; } = "";
    public TransactionType Type { get; set; }
    public string Icon { get; set; } = "category";
    public string Color { get; set; } = "#9E9E9E";
}

public class Transaction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid AccountId { get; set; }
    public Account? Account { get; set; }
    public Guid CategoryId { get; set; }
    public Category? Category { get; set; }
    public string Description { get; set; } = "";
    /// <summary>Sempre positivo; o sinal vem de <see cref="Type"/>.</summary>
    public decimal Amount { get; set; }
    public TransactionType Type { get; set; }
    public DateOnly Date { get; set; }
    public bool IsPaid { get; set; } = true;
}

/// <summary>Tentativas erradas de código de vinculação por número (RN-24). Fica no banco
/// para valer em todas as instâncias da API e sobreviver a reinícios.</summary>
public class LinkAttempt
{
    public string Phone { get; set; } = "";
    public int Failures { get; set; }
    public DateTime WindowStartsAt { get; set; }
}

/// <summary>Limite de gasto mensal por categoria.</summary>
public class Budget
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid CategoryId { get; set; }
    public Category? Category { get; set; }
    /// <summary>Formato yyyy-MM.</summary>
    public string Month { get; set; } = "";
    public decimal Limit { get; set; }
}
