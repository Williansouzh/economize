namespace Financas.Api.Services;

/// <summary>
/// "Hoje" no fuso do usuário (padrão America/Sao_Paulo), não no fuso do servidor.
/// Sem isso, um servidor em UTC viraria o dia às 21h no Brasil.
/// </summary>
public class AppClock(TimeProvider time, IConfiguration config)
{
    private readonly TimeZoneInfo _zone = FindZone(config["App:TimeZone"] ?? "America/Sao_Paulo");

    public DateOnly Today => DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(time.GetUtcNow(), _zone).DateTime);

    private static TimeZoneInfo FindZone(string id)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
        catch (TimeZoneNotFoundException) { return TimeZoneInfo.Utc; }
    }
}
