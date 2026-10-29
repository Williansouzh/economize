using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Financas.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class SemDuplicados : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Nome de categoria único por perfil e tipo, sem diferenciar maiúsculas (RN-31). Índice de
            // expressão, que o modelo do EF não descreve. Produção tinha 0 duplicados em 29/10/2026.
            migrationBuilder.Sql("""
                CREATE UNIQUE INDEX "IX_Categories_UserId_Type_LowerName" ON "Categories" ("UserId", "Type", lower("Name"));
                """);

            migrationBuilder.DropIndex(
                name: "IX_Transactions_AccountId_ExternalId",
                table: "Transactions");

            migrationBuilder.CreateIndex(
                name: "IX_Users_WhatsAppLinkCode",
                table: "Users",
                column: "WhatsAppLinkCode",
                unique: true,
                filter: "\"WhatsAppLinkCode\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_Transactions_AccountId_ExternalId",
                table: "Transactions",
                columns: new[] { "AccountId", "ExternalId" },
                unique: true,
                filter: "\"ExternalId\" IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""DROP INDEX "IX_Categories_UserId_Type_LowerName";""");

            migrationBuilder.DropIndex(
                name: "IX_Users_WhatsAppLinkCode",
                table: "Users");

            migrationBuilder.DropIndex(
                name: "IX_Transactions_AccountId_ExternalId",
                table: "Transactions");

            migrationBuilder.CreateIndex(
                name: "IX_Transactions_AccountId_ExternalId",
                table: "Transactions",
                columns: new[] { "AccountId", "ExternalId" });
        }
    }
}
