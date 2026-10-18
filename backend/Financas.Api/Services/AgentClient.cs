namespace Financas.Api.Services;

/// <summary>
/// Avisa o agente do WhatsApp para apagar o histórico de conversa de um número (RN-30).
/// O histórico fica no banco do agente, que a API não acessa. Sem <c>Agent:Url</c> configurada
/// (desenvolvimento e testes), não faz nada.
/// </summary>
public class AgentClient(HttpClient http, IConfiguration config, ILogger<AgentClient> log)
{
    public async Task ForgetAsync(string phone, CancellationToken ct = default)
    {
        var url = config["Agent:Url"];
        if (string.IsNullOrWhiteSpace(url)) return;
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Post, url.TrimEnd('/') + "/internal/forget")
            {
                Content = JsonContent.Create(new { phone }),
            };
            req.Headers.Add("X-Agent-Key", config["Agent:ApiKey"]);
            using var res = await http.SendAsync(req, ct);
            res.EnsureSuccessStatusCode();
        }
        catch (Exception e)
        {
            // Não bloqueia a exclusão da conta: o agente também apaga o histórico na próxima
            // mensagem desse número, ao ver que ele não está mais vinculado.
            log.LogError(e, "Não foi possível pedir ao agente para apagar o histórico de um número");
        }
    }
}
