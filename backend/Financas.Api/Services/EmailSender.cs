using System.Net;
using System.Net.Mail;

namespace Financas.Api.Services;

public interface IEmailSender
{
    /// <summary>Falso quando não há servidor de e-mail configurado.</summary>
    bool IsConfigured { get; }
    Task SendAsync(string to, string subject, string body);
}

/// <summary>
/// Envio por SMTP com STARTTLS. Serve para qualquer provedor (Resend, Brevo, Amazon SES, Gmail com
/// senha de app). Configuração em "Email": SmtpHost, SmtpPort (padrão 587), Username, Password e From.
/// </summary>
public class SmtpEmailSender(IConfiguration config, ILogger<SmtpEmailSender> log) : IEmailSender
{
    private readonly IConfigurationSection _cfg = config.GetSection("Email");

    public bool IsConfigured => !string.IsNullOrWhiteSpace(_cfg["SmtpHost"]) && !string.IsNullOrWhiteSpace(_cfg["From"]);

    public async Task SendAsync(string to, string subject, string body)
    {
        if (!IsConfigured) throw new InvalidOperationException("E-mail não configurado.");
        using var client = new SmtpClient(_cfg["SmtpHost"], _cfg.GetValue("SmtpPort", 587))
        {
            EnableSsl = true,
            Credentials = new NetworkCredential(_cfg["Username"], _cfg["Password"]),
        };
        using var message = new MailMessage(_cfg["From"]!, to, subject, body);
        await client.SendMailAsync(message);
        log.LogInformation("E-mail \"{Subject}\" enviado", subject);
    }
}

/// <summary>Desenvolvimento sem SMTP: mostra o e-mail no log em vez de enviar.</summary>
public class LogEmailSender(ILogger<LogEmailSender> log) : IEmailSender
{
    public bool IsConfigured => true;

    public Task SendAsync(string to, string subject, string body)
    {
        log.LogWarning("E-mail (não enviado, só em desenvolvimento) para {To}: {Subject}\n{Body}", to, subject, body);
        return Task.CompletedTask;
    }
}
