using Microsoft.Extensions.Caching.Memory;

namespace Financas.Api.Services;

/// <summary>
/// Limita tentativas erradas de código de vinculação por número de WhatsApp,
/// para que ninguém consiga adivinhar o código ativo de outra pessoa.
/// </summary>
public class LinkAttemptLimiter(IMemoryCache cache)
{
    public const int MaxFailures = 5;
    public static readonly TimeSpan Window = TimeSpan.FromMinutes(30);

    private static string Key(string phone) => $"link-fail:{phone}";

    public bool IsBlocked(string phone) =>
        cache.TryGetValue(Key(phone), out Counter? c) && c!.Failures >= MaxFailures;

    public void RegisterFailure(string phone)
    {
        // A janela conta a partir da primeira falha; não é renovada a cada tentativa.
        var counter = cache.GetOrCreate(Key(phone), e =>
        {
            e.AbsoluteExpirationRelativeToNow = Window;
            return new Counter();
        })!;
        Interlocked.Increment(ref counter.Failures);
    }

    public void Reset(string phone) => cache.Remove(Key(phone));

    private class Counter { public int Failures; }
}
