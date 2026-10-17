FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Financas.Api/Financas.Api.csproj Financas.Api/
RUN dotnet restore Financas.Api/Financas.Api.csproj
COPY Financas.Api/ Financas.Api/
RUN dotnet publish Financas.Api/Financas.Api.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
# Banco: ConnectionStrings__Default (PostgreSQL). As migrations são aplicadas na subida.
ENV ASPNETCORE_HTTP_PORTS=5000
EXPOSE 5000
ENTRYPOINT ["dotnet", "Financas.Api.dll"]
