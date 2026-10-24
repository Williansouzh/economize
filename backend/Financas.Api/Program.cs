using System.Text;
using System.Text.Json.Serialization;
using Financas.Api.Data;
using Financas.Api.Endpoints;
using Financas.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.ConfigureHttpJsonOptions(o =>
    o.SerializerOptions.Converters.Add(new JsonStringEnumConverter()));

var connectionString = builder.Configuration.GetConnectionString("Default");
if (string.IsNullOrWhiteSpace(connectionString))
    throw new InvalidOperationException(
        "ConnectionStrings:Default ausente. Ex.: Host=localhost;Database=financas;Username=postgres;Password=... " +
        "(variável de ambiente ConnectionStrings__Default).");
builder.Services.AddDbContext<AppDbContext>(o => o.UseNpgsql(connectionString));

var jwt = builder.Configuration.GetSection("Jwt");
JwtKeyGuard.Validate(jwt["Key"], builder.Environment);
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwt["Issuer"],
            ValidAudience = jwt["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Key"]!)),
        };
        // Recusa o token de conta excluída ou de sessão encerrada em "Sair de todos os aparelhos" (RN-32).
        o.Events = new JwtBearerEvents
        {
            OnTokenValidated = async ctx =>
            {
                var principal = ctx.Principal!;
                var db = ctx.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                var userId = principal.UserId();
                var current = await db.Users.Where(u => u.Id == userId)
                    .Select(u => new { u.TokenVersion, u.LastSeenAt }).FirstOrDefaultAsync();
                // Tokens emitidos antes da RN-32 não têm a versão e valem como 0.
                var version = principal.FindFirst(TokenService.VersionClaim)?.Value ?? "0";
                if (current is null || version != current.TokenVersion.ToString())
                    ctx.Fail("Sessão encerrada.");
                else
                    await ctx.HttpContext.RequestServices.GetRequiredService<ActivityTracker>().TouchAsync(userId, current.LastSeenAt);
            },
        };
    });
builder.Services.AddAuthorization();
builder.Services.AddHttpProtection(builder.Configuration, builder.Environment);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<AppClock>();

builder.Services.AddMemoryCache();
builder.Services.AddScoped<LinkAttemptLimiter>();
builder.Services.AddScoped<AuthRateLimiter>();
builder.Services.AddScoped<AuthRateLimitFilter>();
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<ActivityTracker>();
builder.Services.AddSingleton<AdminAccess>();
// E-mail (RN-38): SMTP se "Email:SmtpHost" estiver configurado; em desenvolvimento sem SMTP, só no log.
if (builder.Environment.IsDevelopment() && string.IsNullOrWhiteSpace(builder.Configuration["Email:SmtpHost"]))
    builder.Services.AddSingleton<IEmailSender, LogEmailSender>();
else
    builder.Services.AddSingleton<IEmailSender, SmtpEmailSender>();
builder.Services.AddScoped<FinanceService>();
builder.Services.AddScoped<InsightsService>();
builder.Services.AddScoped<AnalysisService>();
builder.Services.AddScoped<AiQuota>();
builder.Services.AddScoped<ImportService>();
builder.Services.AddHttpClient<AgentClient>(c => c.Timeout = TimeSpan.FromSeconds(10));
builder.Services.AddHttpClient<DeepSeekClient>(c =>
{
    c.BaseAddress = new Uri(builder.Configuration["DeepSeek:BaseUrl"]!.TrimEnd('/') + "/");
    c.Timeout = TimeSpan.FromSeconds(90);
});

var app = builder.Build();

// Aplica as migrations pendentes na subida, uma réplica por vez (veja DatabaseMigrator).
// Para aplicar fora da API (pipeline de deploy), use Database:MigrateOnStartup=false e "dotnet ef database update".
if (app.Configuration.GetValue("Database:MigrateOnStartup", true))
{
    using var scope = app.Services.CreateScope();
    DatabaseMigrator.Migrate(scope.ServiceProvider.GetRequiredService<AppDbContext>());
}

if (app.Environment.IsDevelopment())
    app.MapOpenApi();

app.UseHttpProtection();
app.UseAuthentication();
app.UseProfileScope();
app.UseAuthorization();
// Depois da autenticação, para o limite global poder separar por usuário.
app.UseRateLimiter();

app.MapGet("/", () => "Finanças API rodando 🚀");
app.MapGet("/health", async (AppDbContext db) => await db.Database.CanConnectAsync()
    ? Results.Ok(new { status = "ok" })
    : Results.Json(new { status = "sem banco" }, statusCode: StatusCodes.Status503ServiceUnavailable));
app.MapAuthEndpoints();
app.MapFinanceEndpoints();
app.MapInsightsEndpoints();
app.MapWhatsAppEndpoints();
app.MapPlanningEndpoints();
app.MapImportEndpoints();
app.MapAdminEndpoints();
app.MapProfileEndpoints();

app.Run();

// Permite que os testes de integração (WebApplicationFactory) enxerguem o Program.
public partial class Program;
