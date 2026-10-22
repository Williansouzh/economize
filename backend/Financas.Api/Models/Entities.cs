namespace Financas.Api.Models;

/// <summary>Transfer move dinheiro entre contas do próprio usuário: não é receita nem despesa.</summary>
public enum TransactionType { Income = 1, Expense = 2, Transfer = 3 }

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
    /// <summary>Obrigatória em receitas e despesas; vazia em transferências.</summary>
    public Guid? CategoryId { get; set; }
    public Category? Category { get; set; }
    /// <summary>Só em transferências: a conta que recebe o dinheiro (sai de <see cref="AccountId"/>).</summary>
    public Guid? DestinationAccountId { get; set; }
    public Account? DestinationAccount { get; set; }
    /// <summary>Chave de idempotência enviada pelo cliente (o agente usa o id da chamada de ferramenta).
    /// Repetir o POST com a mesma chave devolve o lançamento já criado.</summary>
    public string? ExternalId { get; set; }
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
    /// <summary>Primeiro mês em que vale (yyyy-MM).</summary>
    public string Month { get; set; } = "";
    public decimal Limit { get; set; }
    /// <summary>Se true, vale também nos meses seguintes até <see cref="UntilMonth"/>.</summary>
    public bool IsRecurring { get; set; }
    /// <summary>Último mês em que vale (yyyy-MM). Igual a Month quando não repete; null = sem fim.</summary>
    public string? UntilMonth { get; set; }
}

/// <summary>Contador de requisições por janela de 1 minuto, compartilhado entre réplicas (RN-26).</summary>
public class RateLimitCounter
{
    public string Key { get; set; } = "";
    public DateTime WindowStart { get; set; }
    public int Count { get; set; }
}
