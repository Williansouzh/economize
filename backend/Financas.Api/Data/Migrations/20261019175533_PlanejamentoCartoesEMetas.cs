using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Financas.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class PlanejamentoCartoesEMetas : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "ResetAttempts",
                table: "Users",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<DateTime>(
                name: "ResetCodeExpiresAt",
                table: "Users",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "ResetCodeHash",
                table: "Users",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "CreatedAt",
                table: "Transactions",
                type: "timestamp with time zone",
                nullable: false,
                defaultValueSql: "now()");

            migrationBuilder.AddColumn<int>(
                name: "InstallmentCount",
                table: "Transactions",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "InstallmentNumber",
                table: "Transactions",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "SeriesId",
                table: "Transactions",
                type: "uuid",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ClosingDay",
                table: "Accounts",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "CreditLimit",
                table: "Accounts",
                type: "numeric(14,2)",
                precision: 14,
                scale: 2,
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "DueDay",
                table: "Accounts",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "Kind",
                table: "Accounts",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateTable(
                name: "Goals",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    Target = table.Column<decimal>(type: "numeric(14,2)", precision: 14, scale: 2, nullable: false),
                    Saved = table.Column<decimal>(type: "numeric(14,2)", precision: 14, scale: 2, nullable: false),
                    Deadline = table.Column<DateOnly>(type: "date", nullable: true),
                    Icon = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    Color = table.Column<string>(type: "character varying(9)", maxLength: 9, nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Goals", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Transactions_SeriesId",
                table: "Transactions",
                column: "SeriesId");

            migrationBuilder.CreateIndex(
                name: "IX_Goals_UserId",
                table: "Goals",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Goals");

            migrationBuilder.DropIndex(
                name: "IX_Transactions_SeriesId",
                table: "Transactions");

            migrationBuilder.DropColumn(
                name: "ResetAttempts",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "ResetCodeExpiresAt",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "ResetCodeHash",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "CreatedAt",
                table: "Transactions");

            migrationBuilder.DropColumn(
                name: "InstallmentCount",
                table: "Transactions");

            migrationBuilder.DropColumn(
                name: "InstallmentNumber",
                table: "Transactions");

            migrationBuilder.DropColumn(
                name: "SeriesId",
                table: "Transactions");

            migrationBuilder.DropColumn(
                name: "ClosingDay",
                table: "Accounts");

            migrationBuilder.DropColumn(
                name: "CreditLimit",
                table: "Accounts");

            migrationBuilder.DropColumn(
                name: "DueDay",
                table: "Accounts");

            migrationBuilder.DropColumn(
                name: "Kind",
                table: "Accounts");
        }
    }
}
