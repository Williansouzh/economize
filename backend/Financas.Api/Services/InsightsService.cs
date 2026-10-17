using System.Globalization;
using System.Text;
using System.Text.Json;
using Financas.Api.Dtos;
using Financas.Api.Models;

namespace Financas.Api.Services;

/// <summary>Monta um resumo financeiro do usuário e pede análises ao DeepSeek.</summary>
public class InsightsService(FinanceService finance, DeepSeekClient deepSeek)
{
    private static readonly CultureInfo PtBr = new("pt-BR");

    private const string SystemPrompt = """
        Você é um consultor financeiro pessoal brasileiro, direto e empático.
        Analise os dados financeiros do usuário (valores em R$) e dê conselhos práticos e específicos,
        citando categorias e valores reais. Não invente dados que não foram fornecidos.
        Responda sempre em português do Brasil.
        """;

    public async Task<InsightsDto> GetInsightsAsync(Guid userId, string? month, CancellationToken ct)
    {
        var context = await BuildContextAsync(userId, month);
        var prompt = $$"""
            {{context}}

            Gere uma análise e responda APENAS com um JSON válido neste formato:
            {
              "summary": "resumo de 2-3 frases sobre o mês",
              "alerts": ["alertas sobre gastos fora do padrão ou orçamentos estourados"],
              "tips": ["3 a 5 dicas práticas de economia baseadas nos dados"],
              "potentialSavings": 0.0,
              "healthScore": 0
            }
            potentialSavings = estimativa em reais de quanto dá para economizar por mês.
            healthScore = nota de 0 a 100 da saúde financeira do mês.
            """;

        var raw = await deepSeek.ChatAsync(SystemPrompt, prompt, jsonOutput: true, ct);
        try
        {
            var parsed = JsonSerializer.Deserialize<InsightsDto>(raw, JsonSerializerOptions.Web);
            if (parsed is not null)
                return parsed with { Alerts = parsed.Alerts ?? [], Tips = parsed.Tips ?? [] };
        }
        catch (JsonException) { /* cai no fallback abaixo */ }

        return new InsightsDto(raw, [], [], 0, 0);
    }

    public async Task<string> AskAsync(Guid userId, string question, string? month, CancellationToken ct)
    {
        var context = await BuildContextAsync(userId, month);
        var prompt = $"""
            {context}

            Pergunta do usuário: {question}
            Responda de forma curta (até 6 frases), usando os dados acima quando fizer sentido.
            """;
        return await deepSeek.ChatAsync(SystemPrompt, prompt, jsonOutput: false, ct);
    }

    /// <summary>Resumo textual do mês atual + mês anterior para comparação. Não envia dados pessoais.</summary>
    private async Task<string> BuildContextAsync(Guid userId, string? month)
    {
        var (start, end, key) = finance.ParseMonth(month);
        var txs = await finance.GetTransactionsAsync(userId, start, end);
        var prevTxs = await finance.GetTransactionsAsync(userId, start.AddMonths(-1), start.AddDays(-1));
        var budgets = await finance.GetBudgetsAsync(userId, key, txs);
        var accounts = await finance.GetAccountsAsync(userId, end);

        string Money(decimal v) => v.ToString("C", PtBr);
        decimal Sum(IEnumerable<Transaction> t, TransactionType type) => t.Where(x => x.Type == type).Sum(x => x.Amount);

        var sb = new StringBuilder();
        sb.AppendLine($"Mês analisado: {key}");
        sb.AppendLine($"Hoje: {finance.Today:dd/MM/yyyy}");
        sb.AppendLine($"Saldo atual nas contas (só lançamentos pagos até hoje): {Money(accounts.Sum(a => a.Balance))}");
        sb.AppendLine($"Saldo previsto para o fim do mês (inclui pendentes e agendados): {Money(accounts.Sum(a => a.ForecastBalance))}");
        sb.AppendLine($"Receitas do mês: {Money(Sum(txs, TransactionType.Income))}");
        sb.AppendLine($"Despesas do mês: {Money(Sum(txs, TransactionType.Expense))}");
        var pending = txs.Where(t => !t.IsPaid).ToList();
        if (pending.Count > 0)
            sb.AppendLine($"Pendentes no mês — a receber: {Money(Sum(pending, TransactionType.Income))}, a pagar: {Money(Sum(pending, TransactionType.Expense))}");
        sb.AppendLine($"Mês anterior — receitas: {Money(Sum(prevTxs, TransactionType.Income))}, despesas: {Money(Sum(prevTxs, TransactionType.Expense))}");

        var prevByCat = FinanceService.ExpensesByCategory(prevTxs).ToDictionary(c => c.CategoryId, c => c.Total);
        sb.AppendLine("\nDespesas por categoria (mês atual | mês anterior):");
        foreach (var c in FinanceService.ExpensesByCategory(txs))
            sb.AppendLine($"- {c.Name}: {Money(c.Total)} ({c.Percent}%) | {Money(prevByCat.GetValueOrDefault(c.CategoryId))}");

        if (budgets.Count > 0)
        {
            sb.AppendLine("\nOrçamentos (limite → gasto):");
            foreach (var b in budgets)
                sb.AppendLine($"- {b.CategoryName}: {Money(b.Limit)} → {Money(b.Spent)}");
        }

        sb.AppendLine("\nMaiores despesas do mês:");
        foreach (var t in txs.Where(t => t.Type == TransactionType.Expense).OrderByDescending(t => t.Amount).Take(10))
            sb.AppendLine($"- {t.Date:dd/MM} {t.Description} ({t.Category!.Name}): {Money(t.Amount)}");

        if (txs.Count == 0)
            sb.AppendLine("\n(O usuário ainda não registrou transações neste mês.)");

        return sb.ToString();
    }
}
