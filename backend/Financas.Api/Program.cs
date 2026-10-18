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
    .AddJwtBearer(o => o.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidateAudience = true,
        ValidateLifetime = true,
        ValidateIssuerSigningKey = true,
        ValidIssuer = jwt["Issuer"],
        ValidAudience = jwt["Audience"],
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt["Key"]!)),
    });
builder.Services.AddAuthorization();
builder.Services.AddHttpProtection(builder.Configuration, builder.Environment);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<AppClock>();

builder.Services.AddMemoryCache();
builder.Services.AddScoped<LinkAttemptLimiter>();
builder.Services.AddScoped<TokenService>();
builder.Services.AddScoped<FinanceService>();
builder.Services.AddScoped<InsightsService>();
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

app.Run();

// Permite que os testes de integração (WebApplicationFactory) enxerguem o Program.
public partial class Program;
