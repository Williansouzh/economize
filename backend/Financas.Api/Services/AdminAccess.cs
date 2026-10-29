namespace Financas.Api.Services;

/// <summary>
/// Super admin (RN-44): ids de usuário em Admin:UserIds, separados por vírgula (ADMIN_USER_IDS no .env do servidor).
/// É o id e não o e-mail porque o cadastro não confirma o e-mail: quem criasse a conta com um endereço
/// da lista antes do dono viraria admin. Ficam fora do repositório, que é público.
/// </summary>
public class AdminAccess(IConfiguration config)
{
    // Lido a cada chamada (é barato): mudar a configuração não exige recriar o serviço.
    public bool IsAdmin(Guid userId) => (config["Admin:UserIds"] ?? "")
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        .Any(s => Guid.TryParse(s, out var id) && id == userId);
}
