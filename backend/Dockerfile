FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY Financas.Api/Financas.Api.csproj Financas.Api/
RUN dotnet restore Financas.Api/Financas.Api.csproj
COPY Financas.Api/ Financas.Api/
RUN dotnet publish Financas.Api/Financas.Api.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_HTTP_PORTS=5000 \
    ConnectionStrings__Default="Data Source=/data/financas.db"
VOLUME /data
EXPOSE 5000
ENTRYPOINT ["dotnet", "Financas.Api.dll"]
