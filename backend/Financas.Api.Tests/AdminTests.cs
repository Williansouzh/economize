using System.Net;
using System.Net.Http.Json;

namespace Financas.Api.Tests;

// ---------- RN-44: super admin vê cadastros e usuários ativos ----------
public class AdminTests
{
    private record Me(string Email, bool IsAdmin);
    private record DayRow(DateOnly Day, int Signups, int Active);
    private record UserRow(string Name, string Email, DateTime? LastSeenAt, int Transactions);
    private record Stats(int TotalUsers, int NewToday, int New7Days, int ActiveToday, int Active7Days, int Active30Days,
        List<DayRow> Days, List<UserRow> RecentUsers);

    private static ApiFactory Factory() => new() { Settings = { ["Admin:Emails"] = "dono@teste.com, outro@teste.com" } };

    [Fact]
    public async Task So_o_email_configurado_ve_o_painel_e_os_outros_recebem_404()
    {
        using var factory = Factory();
        var admin = await factory.CreateUserClientAsync("Dono@Teste.com");
        var user = await factory.CreateUserClientAsync("ana@teste.com");

        Assert.True((await admin.GetFromJsonAsync<Me>("/api/me"))!.IsAdmin);
        Assert.False((await user.GetFromJsonAsync<Me>("/api/me"))!.IsAdmin);
        Assert.Equal(HttpStatusCode.OK, (await admin.GetAsync("/api/admin/stats")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await user.GetAsync("/api/admin/stats")).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await factory.CreateClient().GetAsync("/api/admin/stats")).StatusCode);
    }

    [Fact]
    public async Task Conta_cadastros_e_ativos_por_dia_no_fuso_do_app()
    {
        using var factory = Factory();
        var admin = await factory.CreateUserClientAsync("dono@teste.com");
        var ana = await factory.CreateUserClientAsync("ana@teste.com");
        await factory.CreateUserClientAsync("bia@teste.com"); // cadastrou e não voltou

        // Ana volta nos dois dias seguintes; usar várias vezes no mesmo dia conta uma vez só.
        for (var i = 0; i < 2; i++)
        {
            factory.Clock.Advance(TimeSpan.FromDays(1));
            await ana.GetAsync("/api/accounts");
            factory.Clock.Advance(TimeSpan.FromHours(1));
            await ana.GetAsync("/api/accounts");
        }
        var stats = (await admin.GetFromJsonAsync<Stats>("/api/admin/stats"))!;

        Assert.Equal(3, stats.TotalUsers);
        Assert.Equal(0, stats.NewToday);
        Assert.Equal(3, stats.New7Days);
        Assert.Equal(2, stats.ActiveToday); // Ana e o admin, que acabou de abrir o painel
        Assert.Equal(3, stats.Active7Days);
        Assert.Equal(30, stats.Days.Count);
        var hoje = stats.Days[^1];
        Assert.Equal(new DateOnly(2026, 10, 19), hoje.Day);
        Assert.Equal(new DayRow(new DateOnly(2026, 10, 17), 3, 3), stats.Days[^3]);
        Assert.Equal(1, stats.Days[^2].Active);
        Assert.Equal(2, hoje.Active);
        Assert.Contains(stats.RecentUsers, u => u.Email == "ana@teste.com" && u.LastSeenAt != null);
    }
}
