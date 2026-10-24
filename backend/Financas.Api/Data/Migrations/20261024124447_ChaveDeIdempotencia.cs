using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Financas.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class ChaveDeIdempotencia : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "IdempotencyKey",
                table: "Transactions",
                type: "character varying(100)",
                maxLength: 100,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Transactions_UserId_IdempotencyKey",
                table: "Transactions",
                columns: new[] { "UserId", "IdempotencyKey" },
                unique: true,
                filter: "\"IdempotencyKey\" IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Transactions_UserId_IdempotencyKey",
                table: "Transactions");

            migrationBuilder.DropColumn(
                name: "IdempotencyKey",
                table: "Transactions");
        }
    }
}
