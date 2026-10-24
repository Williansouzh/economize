using System.Text;
using System.Text.Json;
using Financas.Api.Data;
using Financas.Api.Dtos;
using Financas.Api.Models;
using Microsoft.EntityFrameworkCore;
using UglyToad.PdfPig;

namespace Financas.Api.Services;

/// <summary>
/// Importação de extratos e de gastos detectados nas notificações do banco (RN-42 e RN-43):
/// lê o arquivo, sugere a categoria de cada linha, marca o que já existe e grava o que o usuário confirmar.
/// </summary>
public class ImportService(AppDbContext db, DeepSeekClient deepSeek, AppClock clock)
{
    public const int MaxFileBytes = 5 * 1024 * 1024;
    private const int MaxPdfChars = 40_000;

    public class ImportException(string message, int status = StatusCodes.Status400BadRequest) : Exception(message)
    {
        public int Status { get; } = status;
    }

    public async Task<List<StatementLine>> ParseAsync(string fileName, byte[] content, CancellationToken ct)
    {
        var ext = Path.GetExtension(fileName).ToLowerInvariant();
        var isPdf = ext == ".pdf" || content.AsSpan().StartsWith("%PDF"u8);
        var lines = isPdf ? await ParsePdfAsync(content, ct) : ParseText(ext, content);
        if (lines.Count == 0)
            throw new ImportException(isPdf
                ? "Não encontramos lançamentos nesse PDF. Confira se é o extrato ou a fatura do banco."
                : "Não reconhecemos esse arquivo. Exporte o extrato em OFX ou CSV no app ou site do banco.");
        return lines;
    }

    private static List<StatementLine> ParseText(string ext, byte[] content)
    {
        var text = Decode(content);
        return ext == ".ofx" || text.Contains("<OFX>", StringComparison.OrdinalIgnoreCase) || text.Contains("<STMTTRN>", StringComparison.OrdinalIgnoreCase)
            ? StatementParser.ParseOfx(text)
            : StatementParser.ParseCsv(text);
    }

    /// <summary>UTF-8 quando válido; senão Latin-1 (comum em extratos de bancos tradicionais).</summary>
    private static string Decode(byte[] content)
    {
        try { return new UTF8Encoding(false, true).GetString(content).TrimStart('﻿'); }
        catch (DecoderFallbackException) { return Encoding.Latin1.GetString(content); }
    }

    private async Task<List<StatementLine>> ParsePdfAsync(byte[] content, CancellationToken ct)
    {
        if (!deepSeek.IsConfigured)
            throw new ImportException("A leitura de PDF não está disponível agora. Use o arquivo OFX ou CSV.", StatusCodes.Status503ServiceUnavailable);
        var text = new StringBuilder();
        try
        {
            using var pdf = PdfDocument.Open(content);
            foreach (var page in pdf.GetPages())
            {
                text.AppendLine(string.Join(' ', page.GetWords().Select(w => w.Text)));
                if (text.Length > MaxPdfChars) break;
            }
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            throw new ImportException("Não conseguimos abrir esse PDF. Se ele tiver senha, exporte sem senha ou use OFX/CSV.");
        }
        if (text.Length < 20)
            throw new ImportException("Esse PDF parece ser uma imagem escaneada. Exporte o extrato em OFX ou CSV.");

        var year = clock.Today.Year;
        var prompt = $"""
            Texto extraído de um extrato bancário ou fatura de cartão brasileiro (ano atual: {year}):
            ---
            {(text.Length > MaxPdfChars ? text.ToString(0, MaxPdfChars) : text.ToString())}
            ---
            Liste TODOS os lançamentos (compras, pagamentos, pix, tarifas, estornos, créditos).
            Ignore saldos, totais, limites, resumos e juros projetados.
            Responda só JSON: {"{"}"items":[{"{"}"date":"yyyy-MM-dd","description":"texto curto","amount":12.34,"type":"expense"|"income"{"}"}]{"}"}
            amount sempre positivo. Em fatura de cartão: compras e tarifas são expense; pagamentos e estornos são income.
            Datas sem ano: use o ano do documento (ou {year}).
            """;
        string raw;
        try { raw = await deepSeek.ChatAsync("Você extrai lançamentos de extratos bancários com precisão.", prompt, jsonOutput: true, ct, maxTokens: 8000); }
        catch (HttpRequestException) { throw new ImportException("Não foi possível ler o PDF agora. Tente de novo.", StatusCodes.Status502BadGateway); }

        var lines = new List<(DateOnly, string, decimal, string?)>();
        try
        {
            using var doc = JsonDocument.Parse(raw);
            foreach (var item in doc.RootElement.GetProperty("items").EnumerateArray())
            {
                if (StatementParser.ParseDate(item.GetProperty("date").GetString() ?? "") is not { } d) continue;
                var amount = item.GetProperty("amount") is { ValueKind: JsonValueKind.Number } n ? Math.Abs(n.GetDecimal())
                    : StatementParser.ParseAmount(item.GetProperty("amount").GetString() ?? "") is { } a ? Math.Abs(a) : 0;
                if (amount == 0) continue;
                var income = item.TryGetProperty("type", out var t) && t.GetString() == "income";
                lines.Add((d, item.TryGetProperty("description", out var desc) ? desc.GetString() ?? "" : "", income ? amount : -amount, null));
            }
        }
        catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException or FormatException)
        {
            throw new ImportException("Não conseguimos entender esse PDF. Exporte o extrato em OFX ou CSV.");
        }
        return StatementParser.WithIds(lines);
    }

    /// <summary>Para cada linha: tipo, categoria sugerida e se já existe (mesmo identificador) ou
    /// parece repetida (mesmo valor e tipo, até 3 dias de diferença, lançada à mão ou por outra fonte).</summary>
    public async Task<List<ImportPreviewItem>> PreviewAsync(Guid uid, Guid accountId, IReadOnlyList<ImportLine> lines, CancellationToken ct)
    {
        if (lines.Count == 0) return [];
        var categories = await db.Categories.AsNoTracking().Where(c => c.UserId == uid).ToListAsync(ct);
        var history = await LearnFromHistoryAsync(uid, ct);

        var from = lines.Min(l => l.Date).AddDays(-3);
        var until = lines.Max(l => l.Date).AddDays(3);
        var ids = lines.Where(l => l.ExternalId is not null).Select(l => l.ExternalId!).ToList();
        var imported = (await db.Transactions.AsNoTracking()
            .Where(t => t.UserId == uid && t.AccountId == accountId && t.ExternalId != null && ids.Contains(t.ExternalId))
            .Select(t => t.ExternalId!).ToListAsync(ct)).ToHashSet();
        // Candidatos a repetido: lançamentos da conta no período que não vieram deste mesmo arquivo.
        var existing = await db.Transactions.AsNoTracking()
            .Where(t => t.UserId == uid && t.AccountId == accountId && t.Date >= from && t.Date <= until
                        && (t.ExternalId == null || !ids.Contains(t.ExternalId)))
            .Select(t => new { t.Id, t.Date, t.Amount, t.Type }).ToListAsync(ct);
        var used = new HashSet<Guid>();

        return lines.Select(l =>
        {
            var type = l.Amount < 0 ? TransactionType.Expense : TransactionType.Income;
            var amount = Math.Abs(l.Amount);
            var status = "new";
            if (l.ExternalId is not null && imported.Contains(l.ExternalId)) status = "imported";
            else
            {
                var match = existing
                    .Where(e => !used.Contains(e.Id) && e.Type == type && e.Amount == amount && Math.Abs(e.Date.DayNumber - l.Date.DayNumber) <= 3)
                    .OrderBy(e => Math.Abs(e.Date.DayNumber - l.Date.DayNumber)).FirstOrDefault();
                if (match is not null) { used.Add(match.Id); status = "duplicate"; }
            }
            var normalized = StatementParser.Normalize(l.Description);
            // Pagar a fatura ou mandar dinheiro entre as próprias contas já aparece como transferência.
            var transferLike = TransferHints.Any(normalized.Contains);
            return new ImportPreviewItem(l.Date, l.Description, amount, type, SuggestCategory(normalized, type, categories, history),
                l.ExternalId, status, transferLike);
        }).ToList();
    }

    /// <summary>Grava as linhas confirmadas. Ignora as que já foram importadas antes.</summary>
    public async Task<int> CommitAsync(Guid uid, ImportCommitRequest req, CancellationToken ct)
    {
        if (!await db.Accounts.AnyAsync(a => a.Id == req.AccountId && a.UserId == uid, ct))
            throw new ImportException("Conta inválida.");
        if (req.Items.Count > StatementParser.MaxLines)
            throw new ImportException($"Importe no máximo {StatementParser.MaxLines} lançamentos por vez.");
        var categories = await db.Categories.AsNoTracking().Where(c => c.UserId == uid).ToDictionaryAsync(c => c.Id, ct);
        var ids = req.Items.Where(i => i.ExternalId is not null).Select(i => i.ExternalId!).ToList();
        var already = (await db.Transactions.AsNoTracking()
            .Where(t => t.UserId == uid && t.AccountId == req.AccountId && t.ExternalId != null && ids.Contains(t.ExternalId))
            .Select(t => t.ExternalId!).ToListAsync(ct)).ToHashSet();

        var today = clock.Today;
        var created = 0;
        foreach (var item in req.Items)
        {
            if (item.ExternalId is not null && !already.Add(item.ExternalId)) continue;
            if (item.Amount <= 0 || item.Amount >= 1_000_000_000_000m) throw new ImportException("Valor inválido.");
            if (!categories.TryGetValue(item.CategoryId, out var category) || category.Type != item.Type)
                throw new ImportException("Categoria inválida.");
            var description = (item.Description ?? "").Trim();
            db.Transactions.Add(new Transaction
            {
                UserId = uid, AccountId = req.AccountId, CategoryId = item.CategoryId, Type = item.Type,
                Amount = item.Amount, Date = item.Date, IsPaid = item.Date <= today,
                Description = description.Length > 200 ? description[..200] : description,
                ExternalId = item.ExternalId is { Length: > 100 } e ? e[..100] : item.ExternalId,
            });
            created++;
        }
        await db.SaveChangesAsync(ct);
        return created;
    }

    // ---------- Categoria sugerida ----------

    private static readonly string[] TransferHints =
        ["pagamento de fatura", "pagamento fatura", "pgto fatura", "fatura paga", "aplicacao", "resgate", "transferencia entre contas", "mesma titularidade"];

    /// <summary>Palavras que indicam a categoria padrão (pelo nome, como criado no cadastro). A ordem
    /// importa: "amazon prime" é assinatura antes de "amazon" ser compra, e "mercado livre" é compra
    /// antes de "mercado" ser alimentação. Palavras curtas vão entre espaços para não casar dentro de
    /// outras ("oi" em "boi").</summary>
    private static readonly (string Category, string[] Words)[] Keywords =
    [
        ("Assinaturas", ["netflix", "spotify", "amazon prime", "prime video", "disney", "hbo", "max.com", "youtube", "apple.com", "google one",
            "icloud", "deezer", "globoplay", "paramount", "chatgpt", "openai", "claude.ai"]),
        ("Saúde", ["farmacia", "drogaria", "droga raia", "drogasil", "pague menos", "hospital", "clinica", "laboratorio", "unimed", "odonto", "dentista"]),
        ("Transporte", ["uber", "99app", " 99 ", "99pop", "posto", "combustivel", "shell", "ipiranga", "petrobras", "estacionamento",
            "sem parar", "conectcar", "veloe", " metro ", "onibus", "bilhete unico", "pedagio", "cabify"]),
        ("Compras", ["amazon", "mercado livre", "mercadolivre", "shopee", "shein", "magalu", "magazine luiza", "americanas", "casas bahia",
            "aliexpress", "renner", "riachuelo", " c&a ", " zara ", "centauro", "netshoes"]),
        ("Alimentação", ["ifood", "restaurante", "padaria", "lanchonete", "mercado", "supermercado", "atacadao", "assai", "carrefour",
            "pao de acucar", "hortifruti", "acougue", "burger", "pizza", "mcdonald", " bk ", "subway", " cafe", "rappi", "ze delivery", " bar "]),
        ("Moradia", ["aluguel", "condominio", " energia", " enel", "cemig", "copel", "sabesp", " agua ", " gas ", "comgas", "internet",
            " vivo ", " claro ", " tim ", " oi ", "iptu"]),
        ("Educação", ["escola", "faculdade", "universidade", "curso", "udemy", "alura", "livraria"]),
        ("Lazer", ["cinema", "ingresso", "steam", "playstation", "xbox", "nintendo", "hotel", "airbnb", "booking", "decolar"]),
        ("Salário", ["salario", "folha de pagamento", "proventos", "vencimentos"]),
        ("Investimentos", ["rendimento", "dividendo", "juros sobre capital", " jcp ", " cdb ", "tesouro"]),
    ];

    private async Task<Dictionary<string, (Guid Category, TransactionType Type)>> LearnFromHistoryAsync(Guid uid, CancellationToken ct)
    {
        // A escolha mais recente do usuário para a mesma descrição vence as palavras-chave.
        var recent = await db.Transactions.AsNoTracking().Where(t => t.UserId == uid && t.Description != "")
            .OrderByDescending(t => t.CreatedAt).Take(3000)
            .Select(t => new { t.Description, t.CategoryId, t.Type }).ToListAsync(ct);
        var map = new Dictionary<string, (Guid, TransactionType)>();
        foreach (var t in recent)
            map.TryAdd($"{t.Type}|{Key(StatementParser.Normalize(t.Description))}", (t.CategoryId, t.Type));
        return map;
    }

    /// <summary>As duas primeiras palavras sem números: "UBER *TRIP 1234" e "Uber trip" viram "uber trip".</summary>
    private static string Key(string normalized)
    {
        var words = normalized.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(w => new string(w.Where(char.IsLetter).ToArray()))
            .Where(w => w.Length > 1 && w is not ("compra" or "pix" or "pag" or "pagamento" or "debito" or "credito" or "cartao" or "enviado" or "recebido" or "transferencia" or "de" or "em" or "no" or "na" or "para"))
            .Take(2);
        return string.Join(' ', words);
    }

    private static Guid? SuggestCategory(string normalized, TransactionType type, List<Category> categories,
        Dictionary<string, (Guid Category, TransactionType Type)> history)
    {
        var key = Key(normalized);
        if (key.Length > 0 && history.TryGetValue($"{type}|{key}", out var learned) && categories.Any(c => c.Id == learned.Category))
            return learned.Category;
        var padded = $" {normalized} ";
        foreach (var (name, words) in Keywords)
        {
            if (!words.Any(w => padded.Contains(w, StringComparison.Ordinal))) continue;
            var match = categories.FirstOrDefault(c => c.Type == type && StatementParser.Normalize(c.Name) == StatementParser.Normalize(name));
            if (match is not null) return match.Id;
        }
        var fallback = type == TransactionType.Expense ? "outros" : "outras receitas";
        return (categories.FirstOrDefault(c => c.Type == type && StatementParser.Normalize(c.Name) == fallback)
                ?? categories.FirstOrDefault(c => c.Type == type))?.Id;
    }
}
