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
    /// <summary>Último uso do app ou do WhatsApp, atualizado a cada poucos minutos (RN-44).</summary>
    public DateTime? LastSeenAt { get; set; }

    /// <summary>Número do WhatsApp vinculado (formato wa_id, ex.: 5511999999999).</summary>
    public string? WhatsAppPhone { get; set; }
    /// <summary>Código temporário que o usuário envia ao bot para provar que é dono do número.</summary>
    public string? WhatsAppLinkCode { get; set; }
    public DateTime? WhatsAppLinkCodeExpiresAt { get; set; }

    /// <summary>Hash do código de "esqueci minha senha" enviado por e-mail (RN-38).</summary>
    public string? ResetCodeHash { get; set; }
    public DateTime? ResetCodeExpiresAt { get; set; }
    public int ResetAttempts { get; set; }

    // ---------- Questionário do onboarding (RN-46), base da análise inicial e mensal ----------
    public int? BirthYear { get; set; }
    /// <summary>Sigla da UF, para comparar com a renda da região.</summary>
    public string? State { get; set; }
    /// <summary>Fontes de renda separadas por vírgula (veja <c>AboutRequest.Sources</c>), ex.: "clt,freela".</summary>
    public string? IncomeSources { get; set; }
    /// <summary>Quantos trabalhos ou clientes fixos a pessoa tem (0 = nenhum no momento).</summary>
    public int? JobCount { get; set; }
    /// <summary>Renda mensal aproximada informada no onboarding, somando todas as fontes.</summary>
    public decimal? DeclaredIncome { get; set; }
    public string? MainGoal { get; set; }
    public DateTime? AboutUpdatedAt { get; set; }
}

public enum ProfileKind { Personal = 0, Business = 1 }

/// <summary>
/// Perfil de empresa (PJ/MEI) do usuário (RN-47). O perfil pessoal não tem linha nesta tabela: o id
/// dele é o próprio id do usuário. Contas, categorias, lançamentos, orçamentos, metas e transferências
/// guardam em <c>UserId</c> o id do perfil a que pertencem, então os dois perfis nunca se misturam.
/// </summary>
public class Profile
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OwnerId { get; set; }
    public string Name { get; set; } = "";
    public string? Cnpj { get; set; }
    public bool IsMei { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

/// <summary>Uso da IA por usuário e dia, para a cota diária (RN-48). Contado no banco: vale em todas as réplicas.</summary>
public class AiUsage
{
    public Guid UserId { get; set; }
    public DateOnly Day { get; set; }
    /// <summary>"chat" ou "insights".</summary>
    public string Kind { get; set; } = "";
    public int Count { get; set; }
}

/// <summary>Última análise da IA por perfil e mês (RN-48). Se os dados não mudaram, devolve esta em vez de chamar a IA.</summary>
public class AiCache
{
    public Guid ProfileId { get; set; }
    public string Key { get; set; } = "";
    /// <summary>SHA-256 do contexto enviado à IA.</summary>
    public string ContextHash { get; set; } = "";
    public string Content { get; set; } = "";
    public DateTime CreatedAt { get; set; }
}

/// <summary>Dia (no fuso do app) em que o usuário usou o app ou o WhatsApp, para contar ativos por dia (RN-44).</summary>
public class UserActivity
{
    public Guid UserId { get; set; }
    public DateOnly Day { get; set; }
}

/// <summary>Conta bancária, carteira, poupança etc.</summary>
public class Account
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Name { get; set; } = "";
    public decimal InitialBalance { get; set; }
    public string Color { get; set; } = "#0C7A68";
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
    public string Color { get; set; } = "#668E93";
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
    /// <summary>Origem de um lançamento importado do extrato ou da notificação do banco (RN-42/43),
    /// para não importar a mesma linha duas vezes. Nulo nos lançados à mão.</summary>
    public string? ExternalId { get; set; }
    /// <summary>Cabeçalho Idempotency-Key do POST que criou o lançamento (RN-45). Repetir o POST com a
    /// mesma chave devolve este lançamento em vez de criar outro. O agente usa o id da chamada de ferramenta.</summary>
    public string? IdempotencyKey { get; set; }
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
    public string Color { get; set; } = "#0C7A68";
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

/// <summary>Requisições de login/cadastro por IP numa janela de 1 minuto (RN-26).
/// Fica no banco para o limite ser o mesmo com qualquer número de réplicas.</summary>
public class RateLimitCounter
{
    public string Key { get; set; } = "";
    public DateTime WindowStart { get; set; }
    public int Count { get; set; }
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
