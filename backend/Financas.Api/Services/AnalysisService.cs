using System.Globalization;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Microsoft.EntityFrameworkCore;

namespace Financas.Api.Services;

/// <summary>
/// Análise inicial (pelo questionário) e mensal (pelos lançamentos) da situação financeira (RN-46).
/// É calculada aqui, sem IA: sai na hora, não gasta a cota e não manda dados para fora.
/// </summary>
public class AnalysisService(AppDbContext db, FinanceService finance, AppClock clock, IConfiguration config)
{
    private static readonly CultureInfo PtBr = new("pt-BR");
    private static string Money(decimal v) => Math.Round(v).ToString("C0", PtBr);
    private static string Pct(double v) => $"{Math.Round(v * 100):0}%";

    public decimal MeiLimit => config.GetValue("Mei:AnnualLimit", 81_000m);

    public static readonly string[] Sources =
        ["clt", "servidor", "autonomo", "mei", "estagio", "aposentadoria", "beneficio", "pensao", "aluguel", "investimentos", "outros"];
    public static readonly string[] Goals = ["organizar", "dividas", "reserva", "investir", "sonho", "aposentadoria"];

    public static List<string> SourceList(User u) =>
        (u.IncomeSources ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries).ToList();

    public int? Age(User u) => u.BirthYear is { } y ? clock.Today.Year - y : null;

    public BenchmarkDto? Benchmark(User u, decimal? income)
    {
        if (Age(u) is not { } age) return null;
        var b = IncomeBenchmark.Compare(age, u.State, income);
        return new BenchmarkDto(b.AgeGroup, IncomeBenchmark.AgeGroupLabel(b.AgeGroup), b.Mean, b.Median,
            b.Region, b.RegionName, b.RegionMean, b.Percentile, IncomeBenchmark.Source);
    }

    // ---------- Análise inicial ----------

    public async Task<AnalysisDto?> InitialAsync(Guid userId)
    {
        var u = await db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == userId);
        if (u is null) return null;
        var bench = Benchmark(u, u.DeclaredIncome);
        if (bench is null || u.DeclaredIncome is not > 0)
            return new AnalysisDto("initial", null, "sem_dados", "Conta um pouco sobre você",
                "Com sua idade e quanto você ganha por mês, eu comparo com quem tem a mesma idade no Brasil.",
                null, null, null, bench, null, []);

        var income = u.DeclaredIncome.Value;
        var p = bench.Percentile ?? 0;
        var (status, headline, message) = p switch
        {
            >= 60 => ("acima", "Sua renda está acima da maioria",
                $"Você ganha mais que cerca de {p}% das pessoas de {bench.AgeGroupLabel} que trabalham no Brasil."),
            >= 40 => ("na_media", "Você está no meio do caminho",
                $"Sua renda é parecida com a da maioria das pessoas de {bench.AgeGroupLabel}: metade delas ganha até {Money(bench.Median)}."),
            _ => ("abaixo", "Sua renda está abaixo da média da sua idade",
                $"Metade das pessoas de {bench.AgeGroupLabel} ganha até {Money(bench.Median)}. Aqui o jogo é fazer cada real render, e eu te ajudo nisso."),
        };

        var points = new List<AnalysisPointDto>
        {
            new("bar_chart", "info", $"Média de {bench.AgeGroupLabel} no Brasil: {Money(bench.Mean)}. Ela é puxada para cima por quem ganha muito, por isso a mediana ({Money(bench.Median)}) diz mais."),
        };
        if (bench.Region != "BR")
            points.Add(new("place", "info", $"No {bench.RegionName}, a média para a sua idade é {Money(bench.RegionMean)}."));

        var sources = SourceList(u);
        if (u.JobCount >= 2)
            points.Add(new("work", "info", $"Com {u.JobCount} trabalhos, lance cada renda numa conta própria: fica fácil ver qual compensa mais o seu tempo."));
        if (sources.Count == 1 && sources[0] is not ("aposentadoria" or "investimentos" or "aluguel"))
            points.Add(new("shield", "warn", $"Toda a sua renda vem de uma fonte só. Uma reserva de 6 meses de gastos te protege se ela parar."));
        if (sources.Contains("autonomo") || sources.Contains("mei"))
            points.Add(new("show_chart", "info", "Renda de autônomo varia: planeje o mês pelo valor mais baixo dos últimos meses, não pelo melhor."));
        if (sources.Contains("mei"))
            points.Add(new("storefront", "info", "Use o perfil Empresa para o dinheiro do MEI. Misturar com o pessoal é o erro mais comum de quem empreende."));

        points.Add(new("pie_chart", "good",
            $"Uma referência simples para {Money(income)}: até {Money(income * .5m)} no essencial, {Money(income * .3m)} no resto e {Money(income * .2m)} guardados."));
        var goal = u.MainGoal switch
        {
            "dividas" => "Comece pelas dívidas de juro mais alto, como cartão e cheque especial. Elas crescem mais rápido que qualquer investimento.",
            "reserva" => $"Uma boa primeira meta: {Money(income * 3)} de reserva, o equivalente a 3 meses de renda.",
            "investir" => "Antes de investir, garanta a reserva de emergência. Depois dela, todo mês fica mais leve.",
            "sonho" => "Crie uma meta com data no app: eu calculo quanto guardar por mês para chegar lá.",
            "aposentadoria" => "Para a aposentadoria, o que mais pesa é o tempo: começar com pouco agora vale mais que muito depois.",
            _ => "Lançar tudo por um mês já mostra para onde o dinheiro vai. É o primeiro passo.",
        };
        points.Add(new("flag", "info", goal));

        return new AnalysisDto("initial", null, status, headline, message, income, null, null, bench, null, points);
    }

    // ---------- Análise mensal ----------

    public async Task<AnalysisDto?> MonthlyAsync(Guid userId, Guid profileId, string? month)
    {
        var u = await db.Users.AsNoTracking().FirstOrDefaultAsync(x => x.Id == userId);
        if (u is null) return null;
        var (start, end, key) = finance.ParseMonth(month);
        var txs = await finance.GetTransactionsAsync(profileId, start, end);
        var prev = await finance.GetTransactionsAsync(profileId, start.AddMonths(-1), start.AddDays(-1));
        var business = profileId != userId;
        var current = key == clock.Today.ToString("yyyy-MM");

        var income = txs.Where(t => t.Type == TransactionType.Income).Sum(t => t.Amount);
        var expenses = txs.Where(t => t.Type == TransactionType.Expense).Sum(t => t.Amount);
        if (income == 0 && expenses == 0)
            return new AnalysisDto("monthly", key, "sem_dados", current ? "Seu mês ainda está em branco" : "Nada lançado neste mês",
                "Lance suas receitas e gastos (ou mande no WhatsApp) e eu te mostro como foi o mês.",
                0, 0, null, null, business ? await MeiAsync(profileId, start.Year) : null, []);

        // Pessoal sem receita lançada: usa a renda do questionário como referência.
        var reference = income > 0 ? income : business ? 0 : u.DeclaredIncome ?? 0;
        double? rate = reference > 0 ? (double)((reference - expenses) / reference) : null;
        var left = reference - expenses;
        var soFar = current ? " até agora" : "";

        string status, headline, message;
        if (rate is null)
            (status, headline, message) = ("atencao", "Faltam suas receitas",
                $"Já saíram {Money(expenses)}{soFar}, mas não vi nenhuma entrada. Lance o que você recebeu para eu calcular o que sobra.");
        else if (business)
            (status, headline, message) = rate switch
            {
                >= .2 => ("otimo", "Empresa com bom lucro", $"Sobraram {Money(left)} das vendas{soFar}: margem de {Pct(rate.Value)}."),
                >= .05 => ("bom", "Empresa no azul", $"Lucro de {Money(left)}{soFar}, margem de {Pct(rate.Value)}. Dá para melhorar revendo custos fixos."),
                >= 0 => ("atencao", "Margem apertada", $"Entrou quase o mesmo que saiu{soFar}: sobraram só {Money(left)}."),
                _ => ("critico", "A empresa gastou mais do que vendeu", $"Saíram {Money(-left)} a mais do que entrou{soFar}. Vamos olhar os custos juntos?"),
            };
        else
            (status, headline, message) = rate switch
            {
                >= .2 => ("otimo", "Mês redondo!", $"Você guardou {Pct(rate.Value)} do que entrou{soFar}: {Money(left)}. Continua assim."),
                >= .1 => ("bom", "Mês no azul", $"Sobraram {Money(left)}{soFar} ({Pct(rate.Value)}). Mais um pouco e você chega nos 20%."),
                >= 0 => ("atencao", "No limite", $"Sobrou pouco{soFar}: {Money(left)}, ou {Pct(rate.Value)} do que entrou."),
                _ => ("critico", "Os gastos passaram da renda", $"Saíram {Money(-left)} a mais do que entrou{soFar}. Bora ver onde dá para cortar?"),
            };
        if (income == 0 && !business && reference > 0)
            message += " (Usei a renda que você informou, porque ainda não há receitas lançadas.)";

        var points = new List<AnalysisPointDto>();
        var byCat = FinanceService.ExpensesByCategory(txs);
        if (byCat.FirstOrDefault() is { } top)
            points.Add(new("pie_chart", "info", $"{top.Name} foi o maior gasto: {Money(top.Total)}, {top.Percent:0}% do total."));

        var prevByCat = FinanceService.ExpensesByCategory(prev).ToDictionary(c => c.CategoryId, c => c.Total);
        var jump = byCat.Select(c => (c.Name, Diff: c.Total - prevByCat.GetValueOrDefault(c.CategoryId), Before: prevByCat.GetValueOrDefault(c.CategoryId)))
            .Where(x => x.Before > 0 && x.Diff > 50 && x.Diff / x.Before >= .2m)
            .OrderByDescending(x => x.Diff).FirstOrDefault();
        if (jump.Name is not null)
            points.Add(new("trending_up", "warn", $"{jump.Name} subiu {Money(jump.Diff)} em relação ao mês passado."));

        var budgets = await finance.GetBudgetsAsync(profileId, key, txs);
        var over = budgets.Where(b => b.Spent > b.Limit).ToList();
        if (over.Count > 0)
            points.Add(new("warning", "bad", over.Count == 1
                ? $"O orçamento de {over[0].CategoryName} estourou em {Money(over[0].Spent - over[0].Limit)}."
                : $"{over.Count} orçamentos estouraram: {string.Join(", ", over.Select(b => b.CategoryName))}."));

        var pendingOut = txs.Where(t => t.Type == TransactionType.Expense && !t.IsPaid).Sum(t => t.Amount);
        if (current && pendingOut > 0)
            points.Add(new("event", "info", $"Ainda faltam {Money(pendingOut)} em contas a pagar neste mês."));

        BenchmarkDto? bench = null;
        MeiSummaryDto? mei = null;
        if (business)
        {
            mei = await MeiAsync(profileId, start.Year);
            if (mei.Status != "ok")
                points.Add(new("speed", "warn", mei.Status == "estourou"
                    ? $"O faturamento do ano já passou do teto do MEI ({Money(mei.Limit)}). Fale com um contador sobre o desenquadramento."
                    : $"No ritmo atual, o faturamento do ano chega a {Money(mei.ProjectedRevenue)}, acima do teto de {Money(mei.Limit)}."));
            if (current && clock.Today.Day >= 15 && !txs.Any(t => t.Category!.Name.StartsWith("DAS")))
                points.Add(new("receipt_long", "warn", "Não vi o DAS deste mês. Ele vence todo dia 20."));
            var proLabore = txs.Where(t => t.Category!.Name == "Pró-labore").Sum(t => t.Amount);
            if (proLabore > 0)
                points.Add(new("person", "info", $"Você tirou {Money(proLabore)} de pró-labore. Lance o mesmo valor como receita no perfil Pessoal."));
        }
        else
        {
            if (rate is >= 0 and < .2 && reference > 0)
                points.Add(new("savings", "info", $"Para guardar 20%, os gastos teriam que ficar em até {Money(reference * .8m)}."));
            if (income > 0 && (bench = Benchmark(u, income)) is not null && !current)
                points.Add(new("bar_chart", "info", bench.Percentile >= 50
                    ? $"O que entrou no mês ({Money(income)}) está acima da mediana de quem tem {bench.AgeGroupLabel} ({Money(bench.Median)})."
                    : $"O que entrou no mês ({Money(income)}) está abaixo da mediana de quem tem {bench.AgeGroupLabel} ({Money(bench.Median)})."));
        }

        return new AnalysisDto("monthly", key, status, headline, message, income, expenses,
            rate is null ? null : Math.Round(rate.Value, 3), bench, mei, points);
    }

    // ---------- Teto do MEI ----------

    public async Task<MeiSummaryDto> MeiAsync(Guid profileId, int year)
    {
        var start = new DateOnly(year, 1, 1);
        var end = new DateOnly(year, 12, 31);
        var revenue = await db.Transactions.AsNoTracking()
            .Where(t => t.UserId == profileId && t.Type == TransactionType.Income && t.Date >= start && t.Date <= end)
            .SumAsync(t => t.Amount);
        var today = clock.Today;
        var elapsed = year < today.Year ? 12 : year > today.Year ? 0 : today.Month;
        var monthsLeft = 12 - elapsed + (year == today.Year ? 1 : 0); // o mês atual ainda pode faturar
        var projected = elapsed == 0 ? revenue : Math.Round(revenue / elapsed * 12, 2);
        var room = Math.Max(0, MeiLimit - revenue);
        var status = revenue > MeiLimit ? "estourou" : projected > MeiLimit ? "atencao" : "ok";
        return new MeiSummaryDto(year, revenue, MeiLimit, Math.Round((double)(revenue / MeiLimit) * 100, 1), projected,
            monthsLeft == 0 ? 0 : Math.Round(room / monthsLeft, 2), monthsLeft, status);
    }
}
