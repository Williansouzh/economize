using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

public class RecorrenciaETransferenciaTests
{
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name, decimal Balance, decimal ForecastBalance);
    private record Budget(Guid Id, Guid CategoryId, string Month, decimal Limit, bool Recurring, bool Inherited);
    private record CategoryTotal(string Name, decimal Total);
    private record Dashboard(decimal Income, decimal Expenses, List<Account> Accounts, List<CategoryTotal> ExpensesByCategory);
    private record Transfer(Guid Id, string FromAccountName, string ToAccountName, decimal Amount);
    private record ErrorBody(string Error);
    private record Created(Guid Id);

    private static async Task<List<Budget>> BudgetsAsync(HttpClient client, string month) =>
        (await client.GetFromJsonAsync<List<Budget>>($"/api/budgets?month={month}"))!;

    // ---------- RN-27: orçamento que se repete ----------

    [Fact]
    public async Task Orcamento_recorrente_vale_nos_meses_seguintes_ate_ser_substituido_ou_parado()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var cats = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var comida = cats.Single(c => c.Name == "Alimentação");
        var lazer = cats.Single(c => c.Name == "Lazer");

        await client.PostAsJsonAsync("/api/budgets", new { categoryId = comida.Id, month = "2026-01", limit = 500m, recurring = true });
        await client.PostAsJsonAsync("/api/budgets", new { categoryId = lazer.Id, month = "2026-01", limit = 200m, recurring = false });

        // Fevereiro herda só o recorrente.
        var fev = Assert.Single(await BudgetsAsync(client, "2026-02"));
        Assert.Equal((comida.Id, 500m, true), (fev.CategoryId, fev.Limit, fev.Inherited));
        Assert.Empty(await BudgetsAsync(client, "2025-12"));

        // Março com valor próprio só para ele; abril volta ao de janeiro.
        await client.PostAsJsonAsync("/api/budgets", new { categoryId = comida.Id, month = "2026-03", limit = 300m, recurring = false });
        var mar = Assert.Single(await BudgetsAsync(client, "2026-03"));
        Assert.Equal((300m, false), (mar.Limit, mar.Inherited));
        Assert.Equal(500m, Assert.Single(await BudgetsAsync(client, "2026-04")).Limit);

        // Parar de repetir em maio: maio em diante fica sem orçamento, abril e janeiro continuam.
        var res = await client.DeleteAsync($"/api/budgets/{fev.Id}?month=2026-05");
        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);
        Assert.Empty(await BudgetsAsync(client, "2026-05"));
        Assert.Empty(await BudgetsAsync(client, "2026-09"));
        Assert.Equal(500m, Assert.Single(await BudgetsAsync(client, "2026-04")).Limit);
        Assert.Equal(2, (await BudgetsAsync(client, "2026-01")).Count);
    }

    [Fact]
    public async Task Excluir_no_mes_de_origem_apaga_o_orcamento_recorrente()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var comida = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!.Single(c => c.Name == "Alimentação");
        var created = await (await client.PostAsJsonAsync("/api/budgets",
            new { categoryId = comida.Id, month = "2026-01", limit = 500m, recurring = true })).Content.ReadFromJsonAsync<Created>();

        await client.DeleteAsync($"/api/budgets/{created!.Id}?month=2026-01");

        Assert.Empty(await BudgetsAsync(client, "2026-01"));
        Assert.Empty(await BudgetsAsync(client, "2026-06"));
    }

    // ---------- RN-28: transferência entre contas ----------

    [Fact]
    public async Task Transferencia_move_saldo_sem_contar_como_receita_ou_despesa()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        await client.PostAsJsonAsync("/api/accounts", new { name = "Nubank", initialBalance = 0m });
        var accounts = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!;
        var carteira = accounts.Single(a => a.Name == "Carteira");
        var nubank = accounts.Single(a => a.Name == "Nubank");

        var res = await client.PostAsJsonAsync("/api/transfers", new
        {
            fromAccountId = carteira.Id, toAccountId = nubank.Id, amount = 100m, date = "2026-01-10", description = "Depósito",
        });
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);
        // Pendente: só entra no saldo previsto.
        await client.PostAsJsonAsync("/api/transfers", new
        {
            fromAccountId = nubank.Id, toAccountId = carteira.Id, amount = 30m, date = "2026-01-20", isPaid = false,
        });

        var d = (await client.GetFromJsonAsync<Dashboard>("/api/dashboard?month=2026-01"))!;
        Assert.Equal((0m, 0m), (d.Income, d.Expenses));
        Assert.Empty(d.ExpensesByCategory);
        var c = d.Accounts.Single(a => a.Name == "Carteira");
        var n = d.Accounts.Single(a => a.Name == "Nubank");
        Assert.Equal((-100m, -70m), (c.Balance, c.ForecastBalance));
        Assert.Equal((100m, 70m), (n.Balance, n.ForecastBalance));

        var list = (await client.GetFromJsonAsync<List<Transfer>>("/api/transfers?month=2026-01"))!;
        Assert.Contains(list, t => t is { FromAccountName: "Carteira", ToAccountName: "Nubank", Amount: 100m });
        Assert.Empty((await client.GetFromJsonAsync<List<Transfer>>("/api/transfers?month=2026-02"))!);

        // RN-06: excluir a conta leva junto as transferências dela.
        await client.DeleteAsync($"/api/accounts/{nubank.Id}");
        var after = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!.Single();
        Assert.Equal((0m, 0m), (after.Balance, after.ForecastBalance));
    }

    [Fact]
    public async Task Transferencia_recusa_mesma_conta_e_conta_de_outro_usuario()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var other = await factory.CreateUserClientAsync("outro@teste.com");
        var mine = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!.Single();
        var theirs = (await other.GetFromJsonAsync<List<Account>>("/api/accounts"))!.Single();

        var same = await client.PostAsJsonAsync("/api/transfers",
            new { fromAccountId = mine.Id, toAccountId = mine.Id, amount = 10m, date = "2026-01-10" });
        Assert.Equal(HttpStatusCode.BadRequest, same.StatusCode);
        Assert.Equal("Escolha contas de origem e destino diferentes.", (await same.Content.ReadFromJsonAsync<ErrorBody>())!.Error);

        var foreign = await client.PostAsJsonAsync("/api/transfers",
            new { fromAccountId = mine.Id, toAccountId = theirs.Id, amount = 10m, date = "2026-01-10" });
        Assert.Equal(HttpStatusCode.BadRequest, foreign.StatusCode);
        Assert.Equal("Conta inválida.", (await foreign.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
    }
}
