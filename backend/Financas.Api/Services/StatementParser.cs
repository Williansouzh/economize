using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace Financas.Api.Services;

/// <summary>Uma linha do extrato. <see cref="Amount"/> tem sinal: negativo é saída, positivo é entrada.</summary>
public record StatementLine(DateOnly Date, string Description, decimal Amount, string ExternalId);

/// <summary>
/// Lê extratos e faturas exportados pelos bancos (RN-42): OFX e CSV aqui; PDF passa pela IA
/// (<see cref="ImportService"/>). Cada linha ganha um identificador estável, para que importar o
/// mesmo arquivo duas vezes não duplique nada.
/// </summary>
public static partial class StatementParser
{
    public const int MaxLines = 1000;

    public static List<StatementLine> ParseOfx(string text)
    {
        var lines = new List<(DateOnly, string, decimal, string?)>();
        foreach (Match block in OfxTransaction().Matches(text))
        {
            var body = block.Groups[1].Value;
            var date = Tag(body, "DTPOSTED");
            var amount = Tag(body, "TRNAMT");
            if (date is null || date.Length < 8 || amount is null) continue;
            if (!DateOnly.TryParseExact(date[..8], "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)) continue;
            if (ParseAmount(amount) is not { } value) continue;
            var memo = Tag(body, "MEMO");
            var name = Tag(body, "NAME");
            // Alguns bancos repetem o nome no memo; outros deixam um deles vazio.
            var description = name is null || memo?.Contains(name, StringComparison.OrdinalIgnoreCase) == true ? memo ?? "" :
                memo is null || name.Contains(memo, StringComparison.OrdinalIgnoreCase) ? name : $"{name} - {memo}";
            lines.Add((d, Clean(description), value, Tag(body, "FITID")));
        }
        return WithIds(lines);
    }

    public static List<StatementLine> ParseCsv(string text)
    {
        var rows = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n')
            .Where(l => !string.IsNullOrWhiteSpace(l)).ToList();
        if (rows.Count < 2) return [];

        // O cabeçalho pode vir depois de linhas de título ("Extrato da conta..."): procura nas 10 primeiras.
        for (var h = 0; h < Math.Min(10, rows.Count - 1); h++)
        {
            var sep = new[] { ';', ',', '\t' }.MaxBy(c => SplitCsv(rows[h], c).Count);
            var header = SplitCsv(rows[h], sep).Select(Normalize).ToList();
            var date = Find(header, "data", "date", "data lancamento", "data da compra", "data movimento", "data de lancamento");
            var desc = Find(header, "descricao", "historico", "title", "titulo", "estabelecimento", "lancamento", "memo", "description", "detalhes");
            var amount = Find(header, "valor", "amount", "valor (r$)", "valor r$", "valor em r$", "quantia");
            var credit = Find(header, "entrada", "credito", "creditos", "entradas");
            var debit = Find(header, "saida", "debito", "debitos", "saidas");
            var id = Find(header, "identificador", "id", "fitid");
            if (date < 0 || desc < 0 || (amount < 0 && (credit < 0 || debit < 0))) continue;

            var lines = new List<(DateOnly, string, decimal, string?)>();
            foreach (var row in rows.Skip(h + 1))
            {
                var cols = SplitCsv(row, sep);
                if (cols.Count <= Math.Max(date, desc)) continue;
                if (ParseDate(cols[date]) is not { } d) continue;
                decimal? value = amount >= 0
                    ? (amount < cols.Count ? ParseAmount(cols[amount]) : null)
                    : (credit < cols.Count ? ParseAmount(cols[credit]) ?? 0 : 0) - Math.Abs(debit < cols.Count ? ParseAmount(cols[debit]) ?? 0 : 0);
                if (value is not { } v || v == 0) continue;
                lines.Add((d, Clean(cols[desc]), v, id >= 0 && id < cols.Count ? cols[id] : null));
            }
            return WithIds(lines);
        }
        return [];
    }

    /// <summary>"R$ -1.234,56", "-1234.56", "1.234,56", "(50,00)" → decimal com sinal.</summary>
    public static decimal? ParseAmount(string raw)
    {
        var s = raw.Trim().Replace("R$", "").Replace(" ", "").Replace(" ", "");
        var negative = s.StartsWith('-') || s.EndsWith('-') || (s.StartsWith('(') && s.EndsWith(')'));
        s = s.Trim('-', '+', '(', ')');
        if (s.Length == 0) return null;
        var comma = s.LastIndexOf(',');
        var dot = s.LastIndexOf('.');
        // O separador decimal é o último que aparece; o outro é de milhar.
        s = comma > dot ? s.Replace(".", "").Replace(',', '.') : s.Replace(",", "");
        if (!decimal.TryParse(s, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var v)) return null;
        return negative ? -v : v;
    }

    public static DateOnly? ParseDate(string raw)
    {
        var s = raw.Trim();
        string[] formats = ["dd/MM/yyyy", "d/M/yyyy", "yyyy-MM-dd", "dd/MM/yy", "dd-MM-yyyy", "dd.MM.yyyy"];
        if (s.Length > 10 && s[10] is ' ' or 'T') s = s[..10];
        return DateOnly.TryParseExact(s, formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;
    }

    /// <summary>Identificador estável: o do banco quando existe; senão um hash de data, valor, texto e
    /// da ordem entre linhas iguais (dois cafés iguais no mesmo dia continuam sendo dois).</summary>
    public static List<StatementLine> WithIds(IEnumerable<(DateOnly Date, string Description, decimal Amount, string? BankId)> lines)
    {
        var seen = new Dictionary<string, int>();
        var result = new List<StatementLine>();
        foreach (var (date, description, amount, bankId) in lines.Take(MaxLines))
        {
            var key = $"{date:yyyy-MM-dd}|{amount.ToString(CultureInfo.InvariantCulture)}|{Normalize(description)}";
            var n = seen[key] = seen.GetValueOrDefault(key) + 1;
            var id = string.IsNullOrWhiteSpace(bankId)
                ? "h:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{key}|{n}")))[..32].ToLowerInvariant()
                : "b:" + bankId.Trim()[..Math.Min(bankId.Trim().Length, 90)];
            result.Add(new StatementLine(date, description.Length == 0 ? "Sem descrição" : description, amount, id));
        }
        return result;
    }

    /// <summary>Minúsculas, sem acentos e sem espaços repetidos: para comparar cabeçalhos e descrições.</summary>
    public static string Normalize(string s)
    {
        var decomposed = s.Trim().ToLowerInvariant().Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return Spaces().Replace(sb.ToString(), " ").Trim('"', ' ');
    }

    private static string Clean(string s)
    {
        var t = Spaces().Replace(System.Net.WebUtility.HtmlDecode(s.Trim().Trim('"')), " ");
        return t.Length > 200 ? t[..200] : t;
    }

    private static int Find(List<string> header, params string[] names)
    {
        foreach (var name in names)
        {
            var i = header.IndexOf(name);
            if (i >= 0) return i;
        }
        return -1;
    }

    private static string? Tag(string body, string tag)
    {
        var m = Regex.Match(body, $@"<{tag}>\s*([^<\r\n]*)", RegexOptions.IgnoreCase);
        var v = m.Success ? m.Groups[1].Value.Trim() : null;
        return string.IsNullOrEmpty(v) ? null : v;
    }

    private static List<string> SplitCsv(string line, char sep)
    {
        var cols = new List<string>();
        var sb = new StringBuilder();
        var quoted = false;
        for (var i = 0; i < line.Length; i++)
        {
            var c = line[i];
            if (c == '"')
            {
                if (quoted && i + 1 < line.Length && line[i + 1] == '"') { sb.Append('"'); i++; }
                else quoted = !quoted;
            }
            else if (c == sep && !quoted) { cols.Add(sb.ToString().Trim()); sb.Clear(); }
            else sb.Append(c);
        }
        cols.Add(sb.ToString().Trim());
        return cols;
    }

    [GeneratedRegex(@"<STMTTRN>(.*?)(?:</STMTTRN>|(?=<STMTTRN>)|(?=</BANKTRANLIST>))", RegexOptions.Singleline | RegexOptions.IgnoreCase)]
    private static partial Regex OfxTransaction();

    [GeneratedRegex(@"\s+")]
    private static partial Regex Spaces();
}
