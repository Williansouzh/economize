namespace Financas.Api.Models;

public enum TransactionType { Income = 1, Expense = 2 }

/// <summary>Conta comum (carteira, banco, poupança) ou cartão de crédito com fatura (RN-35).</summary>
public enum AccountKind { Regular = 0, CreditCard = 1 }

public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "";
    public string Email { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    /// <summary>Vai no token; aumentar invalida todas as sessões abertas (RN-32).</summary>
    public int TokenVersion { get; set; }

    /// <summary>Número do WhatsApp vinculado (formato wa_id, ex.: 5511999999999).</summary>
    public string? WhatsAppPhone { get; set; }
    /// <summary>Código temporário que o usuário envia ao bot para provar que é dono do número.</summary>
    public string? WhatsAppLinkCode { get; set; }
    public DateTime? WhatsAppLinkCodeExpiresAt { get; set; }

    /// <summary>Hash do código de "esqueci minha senha" enviado por e-mail (RN-38).</summary>
    public string? ResetCodeHash { get; set; }
    public DateTime? ResetCodeExpiresAt { get; set; }
    public int ResetAttempts { get; set; }
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

    public AccountKind Kind { get; set; }
    /// <summary>Só cartão: limite, dia em que a fatura fecha e dia do vencimento (RN-35).</summary>
    public decimal? CreditLimit { get; set; }
    public int? ClosingDay { get; set; }
    public int? DueDay { get; set; }
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

    /// <summary>Lançamentos criados juntos como fixos ou parcelados compartilham a série (RN-33).</summary>
    public Guid? SeriesId { get; set; }
    /// <summary>Só parcelados: número da parcela (1..N) e total de parcelas.</summary>
    public int? InstallmentNumber { get; set; }
    public int? InstallmentCount { get; set; }
    /// <summary>Quando foi registrado (não a data do lançamento): base da sequência de dias (RN-37).</summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>Meta de economia, como "R$ 5 mil para a viagem até dezembro" (RN-36). O valor guardado
/// é informado pelo usuário e não mexe no saldo das contas.</summary>
public class Goal
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Name { get; set; } = "";
    public decimal Target { get; set; }
    public decimal Saved { get; set; }
    public DateOnly? Deadline { get; set; }
    public string Icon { get; set; } = "savings";
    public string Color { get; set; } = "#00A86B";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
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
    /// <summary>Vale também para os meses seguintes que não tiverem orçamento próprio (RN-27).</summary>
    public bool Recurring { get; set; }
    /// <summary>Primeiro mês (yyyy-MM) em que a repetição para de valer. Nulo = repete sem fim.</summary>
    public string? UntilMonth { get; set; }
}

/// <summary>Dinheiro movido entre duas contas do usuário. Muda os saldos, mas não é receita
/// nem despesa: fica fora dos totais do mês, das categorias e dos orçamentos (RN-28).</summary>
public class Transfer
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid FromAccountId { get; set; }
    public Account? FromAccount { get; set; }
    public Guid ToAccountId { get; set; }
    public Account? ToAccount { get; set; }
    public string Description { get; set; } = "";
    /// <summary>Sempre positivo.</summary>
    public decimal Amount { get; set; }
    public DateOnly Date { get; set; }
    public bool IsPaid { get; set; } = true;
}
