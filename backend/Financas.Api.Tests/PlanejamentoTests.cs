using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using Financas.Api.Endpoints;
using Financas.Api.Services;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace Financas.Api.Tests;

// ---------- RN-33 a RN-40: fixos e parcelados, busca, cartão, metas, sequência, senha e exportação ----------
public class PlanejamentoTests
{
    private record Account(Guid Id, string Name, decimal Balance, string Kind, decimal? OpenInvoice);
    private record Category(Guid Id, string Name, string Type);
    private record Tx(Guid Id, string Description, decimal Amount, DateOnly Date, bool IsPaid,
        Guid? SeriesId, int? InstallmentNumber, int? InstallmentCount);
    private record Invoice(string Month, DateOnly PeriodStart, DateOnly ClosingDate, DateOnly DueDate,
        decimal Total, decimal Paid, bool IsOpen, List<Tx> Items);
    private record Goal(Guid Id, string Name, decimal Target, decimal Saved, double Progress, decimal? MonthlyNeeded);
    private record Achievement(string Id, bool Unlocked);
    private record Progress(int Streak, int BestStreak, bool RegisteredToday, List<Achievement> Achievements);
    private record ErrorBody(string Error);

    private static async Task<(Guid Account, Guid Expense, Guid Income)> RefsAsync(HttpClient c)
    {
        var acc = (await c.GetFromJsonAsync<List<Account>>("/api/accounts"))![0].Id;
        var cats = (await c.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        return (acc, cats.First(x => x.Name == "Compras").Id, cats.First(x => x.Name == "Salário").Id);
    }

    private static Task<HttpResponseMessage> PostTx(HttpClient c, Guid account, Guid category, decimal amount, string date,
        string description = "Teste", string type = "Expense", object? repeat = null, bool isPaid = true) =>
        c.PostAsJsonAsync("/api/transactions", new { accountId = account, categoryId = category, description, amount, type, date, isPaid, repeat });

    // ---------- RN-33 ----------

    [Fact]
    public async Task Parcelado_divide_o_total_e_poe_os_centavos_na_primeira()
    {
        using var factory = new ApiFactory();
        var c = await factory.CreateUserClientAsync();
        var (acc, compras, _) = await RefsAsync(c);

        var res = await PostTx(c, acc, compras, 100m, "2026-01-31", "Celular", repeat: new { kind = "installments", count = 3 });
        Assert.Equal(HttpStatusCode.Created, res.StatusCode);

        var all = new List<Tx>();
        foreach (var m in new[] { "2026-01", "2026-02", "2026-03", "2026-04" })
            all.AddRange((await c.GetFromJsonAsync<List<Tx>>($"/api/transactions?month={m}"))!);
        Assert.Equal(3, all.Count);
        Assert.Equal([33.34m, 33.33m, 33.33m], all.OrderBy(t => t.InstallmentNumber).Select(t => t.Amount));
        Assert.Equal(100m, all.Sum(t => t.Amount));
        // 31/01 → 28/02 → 31/03: em mês curto cai no último dia.
        Assert.Equal([new DateOnly(2026, 1, 31), new DateOnly(2026, 2, 28), new DateOnly(2026, 3, 31)],
            all.OrderBy(t => t.InstallmentNumber).Select(t => t.Date));
        Assert.All(all, t => Assert.Equal(3, t.InstallmentCount));
        Assert.Single(all.Select(t => t.SeriesId).Distinct());
        Assert.Equal([true, false, false], all.OrderBy(t => t.InstallmentNumber).Select(t => t.IsPaid));
    }

    [Fact]
    public async Task Fixo_repete_o_valor_e_excluir_daqui_pra_frente_mantem_os_anteriores()
    {
        using var factory = new ApiFactory();
        var c = await factory.CreateUserClientAsync();
        var (acc, _, salario) = await RefsAsync(c);

        await PostTx(c, acc, salario, 5000m, "2026-10-05", "Salário", "Income", new { kind = "monthly", count = 12 });
        var nov = (await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-11"))!.Single();
        Assert.Equal(5000m, nov.Amount);
        Assert.Null(nov.InstallmentCount);

        // Edita daqui pra frente: muda novembro em diante, outubro fica.
        var put = await c.PutAsJsonAsync($"/api/transactions/{nov.Id}?scope=future", new
        {
            accountId = acc, categoryId = salario, description = "Salário novo", amount = 5500m, type = "Income",
            date = "2026-11-05", isPaid = false,
        });
        Assert.Equal(HttpStatusCode.NoContent, put.StatusCode);
        Assert.Equal(5000m, (await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-10"))!.Single().Amount);
        Assert.Equal(5500m, (await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2027-03"))!.Single().Amount);

        // Exclui de dezembro em diante.
        var dec = (await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-12"))!.Single();
        Assert.Equal(HttpStatusCode.NoContent, (await c.DeleteAsync($"/api/transactions/{dec.Id}?scope=future")).StatusCode);
        Assert.Single((await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-11"))!);
        Assert.Empty((await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-12"))!);
        Assert.Empty((await c.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2027-09"))!);
    }

    [Fact]
    public async Task Repeticao_invalida_e_recusada()
    {
        using var factory = new ApiFactory();
        var c = await factory.CreateUserClientAsync();
        var (acc, compras, _) = await RefsAsync(c);
        Assert.Equal(HttpStatusCode.BadRequest, (await PostTx(c, acc, compras, 10, "2026-10-01", repeat: new { kind = "installments", count = 1 })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await PostTx(c, acc, compras, 10, "2026-10-01", repeat: new { kind = "monthly", count = 61 })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await PostTx(c, acc, compras, 10, "2026-10-01", repeat: new { kind = "weekly", count = 4 })).StatusCode);
    }

    // ---------- RN-34 ----------

    [Fact]
    public async Task Busca_acha_em_qualquer_mes_por_texto_e_categoria_e_nao_mostra_de_outro_usuario()
    {
        using var factory = new ApiFactory();
        var c = await factory.CreateUserClientAsync();
        var other = await factory.CreateUserClientAsync("outro@teste.com");
        var (acc, compras, salario) = await RefsAsync(c);
        await PostTx(c, acc, compras, 50, "2025-03-10", "Farmácia 100%");
        await PostTx(c, acc, compras, 80, "2026-10-01", "Mercado");
        await PostTx(c, acc, salario, 3000, "2026-10-05", "Pagamento", "Income");
        var (oAcc, oCompras, _) = await RefsAsync(other);
        await PostTx(other, oAcc, oCompras, 99, "2026-10-01", "Farmácia do outro");

        var byText = await c.GetFromJsonAsync<List<Tx>>("/api/transactions/search?q=farm");
        Assert.Equal("Farmácia 100%", Assert.Single(byText!).Description);
        // "%" é texto, não curinga.
        Assert.Single((await c.GetFromJsonAsync<List<Tx>>("/api/transactions/search?q=100%25"))!);
        Assert.Empty((await c.GetFromJsonAsync<List<Tx>>("/api/transactions/search?q=%25%25x"))!);
        // Pelo nome da categoria e por filtro.
        Assert.Equal(2, (await c.GetFromJsonAsync<List<Tx>>("/api/transactions/search?q=compras"))!.Count);
        Assert.Single((await c.GetFromJsonAsync<List<Tx>>($"/api/transactions/search?categoryId={salario}"))!);
        Assert.Equal(2, (await c.GetFromJsonAsync<List<Tx>>("/api/transactions/search?type=Expense"))!.Count);
    }

    [Fact]
    public async Task Proximas_contas_lista_so_pendentes_a_partir_de_hoje()
    {
        using var factory = new ApiFactory(); // hoje: 17/10/2026
        var c = await factory.CreateUserClientAsync();
        var (acc, compras, _) = await RefsAsync(c);
        await PostTx(c, acc, compras, 10, "2026-10-16", "Ontem", isPaid: false);
        await PostTx(c, acc, compras, 20, "2026-10-20", "Luz", isPaid: false);
        await PostTx(c, acc, compras, 30, "2026-10-21", "Já paga", isPaid: true);
        await PostTx(c, acc, compras, 40, "2027-01-20", "Longe", isPaid: false);

        var up = await c.GetFromJsonAsync<List<Tx>>("/api/transactions/upcoming?days=30");
        Assert.Equal("Luz", Assert.Single(up!).Description);
    }

    // ---------- RN-35 ----------

    [Fact]
    public void Periodo_da_fatura_respeita_fechamento_vencimento_e_meses_curtos()
    {
        // Fecha dia 3, vence dia 10: fatura de outubro = 03/09 a 02/10, vence 10/10.
        var (start, closing, due) = FinanceService.InvoicePeriod(new DateOnly(2026, 10, 1), 3, 10);
        Assert.Equal((new DateOnly(2026, 9, 3), new DateOnly(2026, 10, 3), new DateOnly(2026, 10, 10)), (start, closing, due));
        // Fecha dia 25, vence dia 5: o vencimento cai no mês seguinte.
        Assert.Equal(new DateOnly(2026, 11, 5), FinanceService.InvoicePeriod(new DateOnly(2026, 10, 1), 25, 5).Due);
        // Fecha dia 31: em fevereiro fecha no dia 28.
        Assert.Equal(new DateOnly(2026, 2, 28), FinanceService.InvoicePeriod(new DateOnly(2026, 2, 1), 31, 10).Closing);
        // Compra no dia do fechamento já vai para a fatura seguinte.
        Assert.Equal(new DateOnly(2026, 11, 1), FinanceService.OpenInvoiceMonth(new DateOnly(2026, 10, 3), 3));
        Assert.Equal(new DateOnly(2026, 10, 1), FinanceService.OpenInvoiceMonth(new DateOnly(2026, 10, 2), 3));
    }

    [Fact]
    public async Task Cartao_mostra_fatura_aberta_e_pagamento_por_transferencia()
    {
        using var factory = new ApiFactory(); // hoje: 17/10/2026
        var c = await factory.CreateUserClientAsync();
        var (wallet, compras, _) = await RefsAsync(c);

        Assert.Equal(HttpStatusCode.BadRequest, (await c.PostAsJsonAsync("/api/accounts",
            new { name = "Cartão", initialBalance = 0, kind = "CreditCard" })).StatusCode);
        var created = await c.PostAsJsonAsync("/api/accounts",
            new { name = "Nubank", initialBalance = 0, kind = "CreditCard", creditLimit = 2000, closingDay = 25, dueDay = 5 });
        var card = (await created.Content.ReadFromJsonAsync<Account>())!.Id;

        await PostTx(c, card, compras, 100, "2026-09-30");  // fatura de outubro (25/09 a 24/10)
        await PostTx(c, card, compras, 50, "2026-10-24");   // ainda outubro
        await PostTx(c, card, compras, 70, "2026-10-25");   // dia do fechamento: novembro
        await PostTx(c, card, compras, 300, "2026-10-10", repeat: new { kind = "installments", count = 3 }); // 100 em out, nov, dez

        var open = (await c.GetFromJsonAsync<Invoice>($"/api/accounts/{card}/invoice"))!;
        Assert.Equal("2026-10", open.Month);
        Assert.Equal(250m, open.Total);
        Assert.True(open.IsOpen);
        Assert.Equal(new DateOnly(2026, 11, 5), open.DueDate);
        var accounts = (await c.GetFromJsonAsync<List<Account>>("/api/accounts"))!;
        Assert.Equal(250m, accounts.Single(a => a.Id == card).OpenInvoice);
        Assert.Null(accounts.Single(a => a.Id == wallet).OpenInvoice);

        var nov = (await c.GetFromJsonAsync<Invoice>($"/api/accounts/{card}/invoice?month=2026-11"))!;
        Assert.Equal(170m, nov.Total);

        // Pagar a fatura = transferir para o cartão depois do fechamento.
        await c.PostAsJsonAsync("/api/transfers", new { fromAccountId = wallet, toAccountId = card, amount = 250, date = "2026-10-28", isPaid = true });
        Assert.Equal(250m, (await c.GetFromJsonAsync<Invoice>($"/api/accounts/{card}/invoice?month=2026-10"))!.Paid);
        Assert.Equal(0m, (await c.GetFromJsonAsync<Invoice>($"/api/accounts/{card}/invoice?month=2026-11"))!.Paid);

        // Conta comum não tem fatura.
        Assert.Equal(HttpStatusCode.NotFound, (await c.GetAsync($"/api/accounts/{wallet}/invoice")).StatusCode);
    }

    // ---------- RN-36 ----------

    [Fact]
    public async Task Meta_calcula_progresso_e_quanto_guardar_por_mes()
    {
        using var factory = new ApiFactory(); // hoje: outubro/2026
        var c = await factory.CreateUserClientAsync();
        var res = await c.PostAsJsonAsync("/api/goals", new { name = "Viagem", target = 1200, deadline = "2026-12-20" });
        var goal = (await res.Content.ReadFromJsonAsync<Goal>())!;
        Assert.Equal(400m, goal.MonthlyNeeded); // out, nov e dez

        goal = (await (await c.PostAsJsonAsync($"/api/goals/{goal.Id}/deposit", new { amount = 300 })).Content.ReadFromJsonAsync<Goal>())!;
        Assert.Equal(0.25, goal.Progress, 3);
        Assert.Equal(300m, goal.MonthlyNeeded);
        goal = (await (await c.PostAsJsonAsync($"/api/goals/{goal.Id}/deposit", new { amount = -1000 })).Content.ReadFromJsonAsync<Goal>())!;
        Assert.Equal(0m, goal.Saved);

        var other = await factory.CreateUserClientAsync("outro@teste.com");
        Assert.Equal(HttpStatusCode.NotFound, (await other.PostAsJsonAsync($"/api/goals/{goal.Id}/deposit", new { amount = 10 })).StatusCode);
        Assert.Empty((await other.GetFromJsonAsync<List<Goal>>("/api/goals"))!);
        Assert.Equal(HttpStatusCode.BadRequest, (await c.PostAsJsonAsync("/api/goals", new { name = "", target = 10 })).StatusCode);
    }

    // ---------- RN-37 ----------

    [Fact]
    public void Sequencia_conta_dias_seguidos_e_nao_zera_de_manha()
    {
        var today = new DateOnly(2026, 10, 17);
        HashSet<DateOnly> D(params int[] days) => days.Select(d => new DateOnly(2026, 10, d)).ToHashSet();
        Assert.Equal((3, 3), PlanningEndpoints.Streaks(D(15, 16, 17), today));
        Assert.Equal((2, 4), PlanningEndpoints.Streaks(D(1, 2, 3, 4, 15, 16), today)); // hoje ainda sem registro
        Assert.Equal((0, 2), PlanningEndpoints.Streaks(D(10, 11), today));
        Assert.Equal((0, 0), PlanningEndpoints.Streaks(D(), today));
    }

    [Fact]
    public async Task Progresso_usa_o_dia_do_registro_e_libera_conquistas()
    {
        using var factory = new ApiFactory();
        var c = await factory.CreateUserClientAsync();
        var (acc, compras, _) = await RefsAsync(c);

        // Um lançamento por dia, de 17 a 19/10 (registrado nesses dias, mesmo com data antiga).
        await PostTx(c, acc, compras, 10, "2026-01-01");
        factory.Clock.Advance(TimeSpan.FromDays(1));
        await PostTx(c, acc, compras, 10, "2026-01-01");
        factory.Clock.Advance(TimeSpan.FromDays(1));
        await PostTx(c, acc, compras, 10, "2026-01-01");

        var p = (await c.GetFromJsonAsync<Progress>("/api/me/progress"))!;
        Assert.Equal(3, p.Streak);
        Assert.True(p.RegisteredToday);
        Assert.True(p.Achievements.Single(a => a.Id == "first_entry").Unlocked);
        Assert.False(p.Achievements.Single(a => a.Id == "streak_7").Unlocked);
        Assert.False(p.Achievements.Single(a => a.Id == "goal_created").Unlocked);

        await c.PostAsJsonAsync("/api/goals", new { name = "Reserva", target = 100 });
        p = (await c.GetFromJsonAsync<Progress>("/api/me/progress"))!;
        Assert.True(p.Achievements.Single(a => a.Id == "goal_created").Unlocked);
    }

    // ---------- RN-38 ----------

    [Fact]
    public async Task Esqueci_a_senha_troca_a_senha_e_derruba_as_sessoes()
    {
        using var factory = new ApiFactory();
        var logged = await factory.CreateUserClientAsync("ana@teste.com");
        var anon = factory.CreateClient();

        Assert.Equal(HttpStatusCode.Accepted, (await anon.PostAsJsonAsync("/api/auth/forgot-password", new { email = "ninguem@teste.com" })).StatusCode);
        Assert.Empty(factory.Emails);

        Assert.Equal(HttpStatusCode.Accepted, (await anon.PostAsJsonAsync("/api/auth/forgot-password", new { email = " ANA@teste.com " })).StatusCode);
        var (to, subject, _) = Assert.Single(factory.Emails);
        Assert.Equal("ana@teste.com", to);
        var code = subject[^6..];

        var curta = await anon.PostAsJsonAsync("/api/auth/reset-password", new { email = "ana@teste.com", code, newPassword = "123" });
        Assert.Equal(HttpStatusCode.BadRequest, curta.StatusCode);
        var ok = await anon.PostAsJsonAsync("/api/auth/reset-password", new { email = "ana@teste.com", code, newPassword = "nova-senha-123" });
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);

        Assert.Equal(HttpStatusCode.Unauthorized, (await logged.GetAsync("/api/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anon.PostAsJsonAsync("/api/auth/login", new { email = "ana@teste.com", password = ApiFactory.Password })).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await anon.PostAsJsonAsync("/api/auth/login", new { email = "ana@teste.com", password = "nova-senha-123" })).StatusCode);
        // O código só vale uma vez.
        Assert.Equal(HttpStatusCode.BadRequest, (await anon.PostAsJsonAsync("/api/auth/reset-password", new { email = "ana@teste.com", code, newPassword = "outra-senha-123" })).StatusCode);
    }

    [Fact]
    public async Task Codigo_de_senha_vence_e_bloqueia_depois_de_5_erros()
    {
        using var factory = new ApiFactory();
        await factory.CreateUserClientAsync("ana@teste.com");
        var anon = factory.CreateClient();

        await anon.PostAsJsonAsync("/api/auth/forgot-password", new { email = "ana@teste.com" });
        var code = factory.Emails[^1].Subject[^6..];
        var wrong = code == "111111" ? "222222" : "111111";
        for (var i = 0; i < 5; i++)
            await anon.PostAsJsonAsync("/api/auth/reset-password", new { email = "ana@teste.com", code = wrong, newPassword = "nova-senha-123" });
        Assert.Equal(HttpStatusCode.BadRequest, (await anon.PostAsJsonAsync("/api/auth/reset-password", new { email = "ana@teste.com", code, newPassword = "nova-senha-123" })).StatusCode);

        await anon.PostAsJsonAsync("/api/auth/forgot-password", new { email = "ana@teste.com" });
        code = factory.Emails[^1].Subject[^6..];
        factory.Clock.Advance(TimeSpan.FromMinutes(16));
        Assert.Equal(HttpStatusCode.BadRequest, (await anon.PostAsJsonAsync("/api/auth/reset-password", new { email = "ana@teste.com", code, newPassword = "nova-senha-123" })).StatusCode);
    }

    [Fact]
    public async Task Sem_email_configurado_a_recuperacao_avisa_que_nao_esta_disponivel()
    {
        using var factory = new ApiFactory { EmailConfigured = false };
        var res = await factory.CreateClient().PostAsJsonAsync("/api/auth/forgot-password", new { email = "ana@teste.com" });
        Assert.Equal(HttpStatusCode.ServiceUnavailable, res.StatusCode);
        Assert.Contains("ainda não está disponível", (await res.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
    }

    // ---------- RN-40 e erros do app ----------

    [Fact]
    public async Task Exporta_csv_para_excel_sem_formulas_e_so_do_usuario()
    {
        using var factory = new ApiFactory();
        var c = await factory.CreateUserClientAsync();
        var (acc, compras, _) = await RefsAsync(c);
        await PostTx(c, acc, compras, 1234.5m, "2026-10-02", "=HYPERLINK(\"x\")");
        await PostTx(c, acc, compras, 10, "2026-10-01", "Pão; leite");

        var res = await c.GetAsync("/api/export/transactions.csv");
        Assert.Equal("text/csv", res.Content.Headers.ContentType!.MediaType);
        var bytes = await res.Content.ReadAsByteArrayAsync();
        Assert.Equal(Encoding.UTF8.GetPreamble(), bytes[..3]);
        var lines = Encoding.UTF8.GetString(bytes[3..]).Split("\r\n", StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal("Data;Descrição;Categoria;Conta;Tipo;Valor;Situação", lines[0]);
        Assert.Equal("01/10/2026;\"Pão; leite\";Compras;Carteira;Despesa;-10,00;Pago", lines[1]);
        Assert.StartsWith("02/10/2026;\"'=HYPERLINK(\"\"x\"\")\";", lines[2]);
        Assert.Contains("-1234,50", lines[2]);

        var anon = factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anon.GetAsync("/api/export/transactions.csv")).StatusCode);
    }

    [Fact]
    public async Task Erro_do_app_e_aceito_sem_login()
    {
        using var factory = new ApiFactory();
        var res = await factory.CreateClient().PostAsJsonAsync("/api/client-errors",
            new { message = "Null check", stack = new string('x', 10_000), platform = "android", version = "1.0.3" });
        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);
    }

    [Fact]
    public async Task Excluir_conta_apaga_as_metas()
    {
        using var factory = new ApiFactory();
        var c = await factory.CreateUserClientAsync();
        await c.PostAsJsonAsync("/api/goals", new { name = "Reserva", target = 100 });
        var del = new HttpRequestMessage(HttpMethod.Delete, "/api/me") { Content = JsonContent.Create(new { password = ApiFactory.Password }) };
        Assert.Equal(HttpStatusCode.NoContent, (await c.SendAsync(del)).StatusCode);

        using var scope = factory.Services.CreateScope();
        Assert.Equal(0, await scope.ServiceProvider.GetRequiredService<Financas.Api.Data.AppDbContext>().Goals.CountAsync());
    }
}
