using System.Net;
using System.Net.Http.Json;
using System.Text;
using Financas.Api.Services;
using UglyToad.PdfPig.Fonts.Standard14Fonts;
using UglyToad.PdfPig.Writer;

namespace Financas.Api.Tests;

// ---------- RN-42: importação de extrato · RN-43: gastos detectados nas notificações ----------
public class ImportacaoTests
{
    private record Category(Guid Id, string Name, string Type);
    private record Account(Guid Id, string Name);
    private record Line(DateOnly Date, string Description, decimal Amount, string ExternalId);
    private record Parsed(List<Line> Items);
    private record Preview(DateOnly Date, string Description, decimal Amount, string Type, Guid? CategoryId, string? ExternalId, string Status, bool TransferLike);
    private record CommitResult(int Created);
    private record ErrorBody(string Error);
    private record Tx(string Description, decimal Amount, string Type, DateOnly Date, Guid CategoryId);

    // ----- Leitura dos arquivos (sem banco) -----

    [Fact]
    public void Le_ofx_no_formato_sgml_sem_tags_de_fechamento()
    {
        const string ofx = """
            OFXHEADER:100
            DATA:OFXSGML
            <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
            <STMTTRN>
            <TRNTYPE>DEBIT
            <DTPOSTED>20261005120000[-3:BRT]
            <TRNAMT>-42.90
            <FITID>abc123
            <MEMO>Compra no débito - PADARIA REAL
            <STMTTRN>
            <TRNTYPE>CREDIT
            <DTPOSTED>20261006
            <TRNAMT>3500.00
            <FITID>xyz789
            <NAME>SALARIO EMPRESA
            </BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
            """;

        var lines = StatementParser.ParseOfx(ofx);

        Assert.Equal(2, lines.Count);
        Assert.Equal(new DateOnly(2026, 10, 5), lines[0].Date);
        Assert.Equal(-42.90m, lines[0].Amount);
        Assert.Equal("Compra no débito - PADARIA REAL", lines[0].Description);
        Assert.Equal("b:abc123", lines[0].ExternalId);
        Assert.Equal(3500m, lines[1].Amount);
        Assert.Equal("SALARIO EMPRESA", lines[1].Description);
    }

    [Fact]
    public void Le_csv_da_conta_do_nubank_e_csv_com_ponto_e_virgula_entrada_e_saida()
    {
        const string nubank = """
            Data,Valor,Identificador,Descrição
            05/10/2026,-42.90,6702a1b2-0000,Compra no débito - Padaria Real
            06/10/2026,1500.00,6702a1b2-0001,"Transferência recebida pelo Pix - FULANO, DE TAL"
            """;
        var a = StatementParser.ParseCsv(nubank);
        Assert.Equal([-42.90m, 1500m], a.Select(l => l.Amount));
        Assert.Equal("Transferência recebida pelo Pix - FULANO, DE TAL", a[1].Description);
        Assert.Equal("b:6702a1b2-0001", a[1].ExternalId);

        const string banco = """
            Extrato de conta corrente
            Agência 1234 Conta 56789-0
            Data;Histórico;Entrada;Saída;Saldo
            01/10/2026;PIX RECEBIDO MARIA;1.200,50;;1.200,50
            02/10/2026;CONTA DE LUZ ENEL;;-235,10;965,40
            02/10/2026;SALDO DO DIA;;;965,40
            """;
        var b = StatementParser.ParseCsv(banco);
        Assert.Equal([1200.50m, -235.10m], b.Select(l => l.Amount));
        Assert.StartsWith("h:", b[0].ExternalId);
    }

    [Fact]
    public void Linhas_iguais_no_mesmo_dia_continuam_separadas_e_o_identificador_e_estavel()
    {
        const string csv = "date,title,amount\n2026-10-05,Café,6.50\n2026-10-05,Café,6.50\n";
        var first = StatementParser.ParseCsv(csv);
        var again = StatementParser.ParseCsv(csv);
        Assert.Equal(2, first.Count);
        Assert.NotEqual(first[0].ExternalId, first[1].ExternalId);
        Assert.Equal(first.Select(l => l.ExternalId), again.Select(l => l.ExternalId));
    }

    [Theory]
    [InlineData("R$ -1.234,56", -1234.56)]
    [InlineData("1234.56", 1234.56)]
    [InlineData("(50,00)", -50)]
    [InlineData("1,234.56", 1234.56)]
    [InlineData("-0,99", -0.99)]
    public void Entende_valores_nos_formatos_brasileiro_e_americano(string raw, double expected) =>
        Assert.Equal((decimal)expected, StatementParser.ParseAmount(raw));

    // ----- API -----

    private static object File(string name, string content) =>
        new { fileName = name, content = Convert.ToBase64String(Encoding.UTF8.GetBytes(content)) };

    [Fact]
    public async Task Importar_sugere_categoria_marca_repetidos_e_nao_duplica_ao_importar_de_novo()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var cats = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!;
        var wallet = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!.Single();
        Guid Cat(string name) => cats.Single(c => c.Name == name).Id;

        // Já lançado à mão: o mercado (vai aparecer como repetido) e um "Uber" que o usuário põe em Lazer.
        await client.PostAsJsonAsync("/api/transactions", new
        {
            accountId = wallet.Id, categoryId = Cat("Alimentação"), description = "mercado", amount = 120m, type = "Expense", date = "2026-10-04",
        });
        await client.PostAsJsonAsync("/api/transactions", new
        {
            accountId = wallet.Id, categoryId = Cat("Lazer"), description = "UBER *TRIP", amount = 18m, type = "Expense", date = "2026-09-01",
        });

        const string csv = """
            Data,Valor,Identificador,Descrição
            05/10/2026,-120.00,id-1,Compra no débito - Supermercado Bom Preço
            06/10/2026,-25.40,id-2,Uber Trip 8823
            07/10/2026,-39.90,id-3,NETFLIX.COM
            08/10/2026,-500.00,id-4,Pagamento de fatura
            09/10/2026,3000.00,id-5,Salario Empresa X
            10/10/2026,-12.00,id-6,Loja desconhecida
            """;
        var parsed = await (await client.PostAsJsonAsync("/api/import/parse", File("extrato.csv", csv))).Content.ReadFromJsonAsync<Parsed>();
        Assert.Equal(6, parsed!.Items.Count);

        var preview = await (await client.PostAsJsonAsync("/api/import/preview", new { accountId = wallet.Id, items = parsed.Items }))
            .Content.ReadFromJsonAsync<List<Preview>>();
        Assert.Equal("duplicate", preview![0].Status);                 // mesmo valor, 1 dia depois do lançado à mão
        Assert.Equal(Cat("Lazer"), preview[1].CategoryId);              // aprendeu com o histórico, venceu a palavra "uber"
        Assert.Equal(Cat("Assinaturas"), preview[2].CategoryId);
        Assert.True(preview[3].TransferLike);
        Assert.Equal(("Income", Cat("Salário")), (preview[4].Type, preview[4].CategoryId));
        Assert.Equal(Cat("Outros"), preview[5].CategoryId);
        Assert.All(preview, p => Assert.True(p.Amount > 0));

        var chosen = preview.Where(p => p.Status == "new" && !p.TransferLike).ToList();
        var items = chosen.Select(p => new { p.Date, p.Description, p.Amount, p.Type, categoryId = p.CategoryId, p.ExternalId }).ToList();
        var res = await client.PostAsJsonAsync("/api/import/commit", new { accountId = wallet.Id, items });
        Assert.Equal(4, (await res.Content.ReadFromJsonAsync<CommitResult>())!.Created);

        // De novo o mesmo arquivo: tudo aparece como já importado e nada é gravado em dobro.
        var again = await (await client.PostAsJsonAsync("/api/import/preview", new { accountId = wallet.Id, items = parsed.Items }))
            .Content.ReadFromJsonAsync<List<Preview>>();
        Assert.Equal(4, again!.Count(p => p.Status == "imported"));
        res = await client.PostAsJsonAsync("/api/import/commit", new { accountId = wallet.Id, items });
        Assert.Equal(0, (await res.Content.ReadFromJsonAsync<CommitResult>())!.Created);

        var october = (await client.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-10"))!;
        Assert.Equal(5, october.Count); // o mercado lançado à mão + 4 importados
        Assert.Contains(october, t => t.Description == "NETFLIX.COM" && t.Amount == 39.90m);
    }

    [Fact]
    public async Task Gasto_detectado_na_notificacao_usa_o_mesmo_fluxo_e_nao_entra_duas_vezes()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync();
        var wallet = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!.Single();
        var line = new { date = "2026-10-17", description = "PADARIA REAL", amount = -8.5m, externalId = "n:com.nu.production:abc" };

        var preview = await (await client.PostAsJsonAsync("/api/import/preview", new { accountId = wallet.Id, items = new[] { line } }))
            .Content.ReadFromJsonAsync<List<Preview>>();
        var p = Assert.Single(preview!);
        var item = new { p.Date, p.Description, p.Amount, p.Type, categoryId = p.CategoryId, p.ExternalId };

        for (var i = 0; i < 2; i++)
            await client.PostAsJsonAsync("/api/import/commit", new { accountId = wallet.Id, items = new[] { item } });

        Assert.Single((await client.GetFromJsonAsync<List<Tx>>("/api/transactions?month=2026-10"))!);
    }

    [Fact]
    public async Task Nao_importa_em_conta_ou_categoria_de_outro_usuario_nem_arquivo_desconhecido()
    {
        using var factory = new ApiFactory();
        var client = await factory.CreateUserClientAsync("eu@teste.com");
        var other = await factory.CreateUserClientAsync("outro@teste.com");
        var mine = (await client.GetFromJsonAsync<List<Account>>("/api/accounts"))!.Single();
        var theirs = (await other.GetFromJsonAsync<List<Account>>("/api/accounts"))!.Single();
        var theirCat = (await other.GetFromJsonAsync<List<Category>>("/api/categories"))!.First(c => c.Type == "Expense");
        var myCat = (await client.GetFromJsonAsync<List<Category>>("/api/categories"))!.First(c => c.Type == "Expense");

        object Item(Guid cat) => new { date = "2026-10-10", description = "x", amount = 10m, type = "Expense", categoryId = cat, externalId = "h:1" };
        var res = await client.PostAsJsonAsync("/api/import/commit", new { accountId = theirs.Id, items = new[] { Item(myCat.Id) } });
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
        res = await client.PostAsJsonAsync("/api/import/commit", new { accountId = mine.Id, items = new[] { Item(theirCat.Id) } });
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);

        res = await client.PostAsJsonAsync("/api/import/parse", File("foto.txt", "isto não é um extrato"));
        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
        Assert.Contains("OFX ou CSV", (await res.Content.ReadFromJsonAsync<ErrorBody>())!.Error);
    }

    private static byte[] Pdf(string text)
    {
        var builder = new PdfDocumentBuilder();
        var font = builder.AddStandard14Font(Standard14Font.Helvetica);
        builder.AddPage(UglyToad.PdfPig.Content.PageSize.A4).AddText(text, 10, new UglyToad.PdfPig.Core.PdfPoint(40, 700), font);
        return builder.Build();
    }

    [Fact]
    public async Task Fatura_em_pdf_e_lida_pela_ia_e_sem_ia_pede_ofx_ou_csv()
    {
        var pdf = new { fileName = "fatura.pdf", content = Convert.ToBase64String(Pdf("Fatura Outubro 05 OUT IFOOD RESTAURANTE 54,90 07 OUT PAGAMENTO RECEBIDO 800,00")) };

        using (var semIa = new ApiFactory { Settings = { ["DeepSeek:ApiKey"] = "" } })
        {
            var client = await semIa.CreateUserClientAsync();
            var res = await client.PostAsJsonAsync("/api/import/parse", pdf);
            Assert.Equal(HttpStatusCode.ServiceUnavailable, res.StatusCode);
        }

        using var factory = new ApiFactory
        {
            DeepSeekReply = """{"items":[{"date":"2026-10-05","description":"IFOOD RESTAURANTE","amount":54.9,"type":"expense"},{"date":"2026-10-07","description":"PAGAMENTO RECEBIDO","amount":800,"type":"income"}]}""",
        };
        var user = await factory.CreateUserClientAsync();
        var parsed = await (await user.PostAsJsonAsync("/api/import/parse", pdf)).Content.ReadFromJsonAsync<Parsed>();

        Assert.Equal([-54.9m, 800m], parsed!.Items.Select(i => i.Amount));
        Assert.Contains("IFOOD RESTAURANTE", Assert.Single(factory.DeepSeekCalls)); // o texto do PDF foi para a IA
    }
}
