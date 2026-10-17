using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Financas.Api.Services;

/// <summary>
/// Cliente da API do DeepSeek (compatível com o formato OpenAI /chat/completions).
/// Docs: https://api-docs.deepseek.com
/// </summary>
public class DeepSeekClient(HttpClient http, IConfiguration config, ILogger<DeepSeekClient> logger)
{
    private readonly string _model = config["DeepSeek:Model"] ?? "deepseek-chat";

    public bool IsConfigured => !string.IsNullOrWhiteSpace(config["DeepSeek:ApiKey"]);

    public async Task<string> ChatAsync(string systemPrompt, string userPrompt, bool jsonOutput,
        CancellationToken ct = default)
    {
        var body = new ChatCompletionRequest
        {
            Model = _model,
            Messages =
            [
                new("system", systemPrompt),
                new("user", userPrompt),
            ],
            Temperature = 0.4,
            ResponseFormat = jsonOutput ? new ResponseFormat("json_object") : null,
        };

        using var req = new HttpRequestMessage(HttpMethod.Post, "chat/completions")
        {
            Content = JsonContent.Create(body),
        };
        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", config["DeepSeek:ApiKey"]);

        using var res = await http.SendAsync(req, ct);
        if (!res.IsSuccessStatusCode)
        {
            var error = await res.Content.ReadAsStringAsync(ct);
            logger.LogError("DeepSeek retornou {Status}: {Error}", res.StatusCode, error);
            throw new HttpRequestException($"DeepSeek retornou {(int)res.StatusCode}");
        }

        var result = await res.Content.ReadFromJsonAsync<ChatCompletionResponse>(ct);
        return result?.Choices.FirstOrDefault()?.Message.Content ?? "";
    }

    private record ChatMessage(
        [property: JsonPropertyName("role")] string Role,
        [property: JsonPropertyName("content")] string Content);

    private record ResponseFormat([property: JsonPropertyName("type")] string Type);

    private class ChatCompletionRequest
    {
        [JsonPropertyName("model")] public string Model { get; init; } = "";
        [JsonPropertyName("messages")] public List<ChatMessage> Messages { get; init; } = [];
        [JsonPropertyName("temperature")] public double Temperature { get; init; }
        [JsonPropertyName("response_format")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public ResponseFormat? ResponseFormat { get; init; }
    }

    private class ChatCompletionResponse
    {
        [JsonPropertyName("choices")] public List<Choice> Choices { get; init; } = [];
    }

    private class Choice
    {
        [JsonPropertyName("message")] public ChatMessage Message { get; init; } = new("assistant", "");
    }
}
