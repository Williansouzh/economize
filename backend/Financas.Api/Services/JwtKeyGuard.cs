using System.Text;

namespace Financas.Api.Services;

/// <summary>Impede a API de subir com uma chave JWT ausente, curta ou de desenvolvimento fora do ambiente de dev.</summary>
public static class JwtKeyGuard
{
    public const string DevelopmentKey = "chave-de-desenvolvimento-local-nao-use-em-producao-0001";

    public static void Validate(string? key, IHostEnvironment env)
    {
        if (string.IsNullOrWhiteSpace(key) || Encoding.UTF8.GetByteCount(key) < 32)
            throw new InvalidOperationException(
                "Jwt:Key ausente ou curta (mínimo 32 caracteres). Defina com " +
                "'dotnet user-secrets set \"Jwt:Key\" \"...\"' ou com a variável de ambiente Jwt__Key.");

        if (key == DevelopmentKey && !env.IsDevelopment())
            throw new InvalidOperationException(
                "A chave JWT de desenvolvimento não pode ser usada fora do ambiente Development. Defina Jwt__Key.");
    }
}
