using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Financas.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class PaletaDeCategorias : Migration
    {
        /// <summary>
        /// Paleta nova (direção de arte, out/2026): as 15 cores Material saturadas de categorias e metas
        /// viram as 10 cores harmonizadas. As categorias padrão vão para a cor pensada para elas; o resto,
        /// para o tom mais próximo. Contas mantêm a cor do banco.
        /// </summary>
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""UPDATE "Categories" SET "Color" = '#008E96' WHERE "Name" = 'Saúde' AND upper("Color") = '#E91E63';""");
            migrationBuilder.Sql("""UPDATE "Categories" SET "Color" = '#8B66B3' WHERE "Name" = 'Lazer' AND upper("Color") = '#FF9800';""");
            migrationBuilder.Sql("""UPDATE "Categories" SET "Color" = '#A85C90' WHERE "Name" = 'Compras' AND upper("Color") = '#9C27B0';""");
            migrationBuilder.Sql("""UPDATE "Categories" SET "Color" = '#3080BC' WHERE "Name" = 'Investimentos' AND upper("Color") = '#8BC34A';""");
            migrationBuilder.Sql("""UPDATE "Categories" SET "Color" = '#668E93' WHERE "Name" = 'Outras receitas' AND upper("Color") = '#CDDC39';""");
            migrationBuilder.Sql("""UPDATE "Categories" SET "Color" = '#A85C90' WHERE "Name" = 'Marketing' AND upper("Color") = '#FF9800';""");
            foreach (var table in new[] { "Categories", "Goals" })
            {
                migrationBuilder.Sql($"""
                    UPDATE "{table}" SET "Color" = CASE upper("Color")
                    WHEN '#E53935' THEN '#B55E43'
                    WHEN '#F44336' THEN '#B55E43'
                    WHEN '#F4511E' THEN '#B55E43'
                    WHEN '#FF5722' THEN '#B55E43'
                    WHEN '#FB8C00' THEN '#A86B16'
                    WHEN '#FF9800' THEN '#A86B16'
                    WHEN '#6D4C41' THEN '#A86B16'
                    WHEN '#795548' THEN '#A86B16'
                    WHEN '#F9A825' THEN '#728426'
                    WHEN '#CDDC39' THEN '#728426'
                    WHEN '#7CB342' THEN '#728426'
                    WHEN '#43A047' THEN '#728426'
                    WHEN '#4CAF50' THEN '#728426'
                    WHEN '#8BC34A' THEN '#728426'
                    WHEN '#00897B' THEN '#008E96'
                    WHEN '#009688' THEN '#008E96'
                    WHEN '#00ACC1' THEN '#008E96'
                    WHEN '#0C7A68' THEN '#008E96'
                    WHEN '#1E88E5' THEN '#3080BC'
                    WHEN '#2196F3' THEN '#3080BC'
                    WHEN '#3949AB' THEN '#6673C1'
                    WHEN '#3F51B5' THEN '#6673C1'
                    WHEN '#5E35B1' THEN '#6673C1'
                    WHEN '#8E24AA' THEN '#8B66B3'
                    WHEN '#9C27B0' THEN '#8B66B3'
                    WHEN '#D81B60' THEN '#A85C90'
                    WHEN '#E91E63' THEN '#A85C90'
                    WHEN '#546E7A' THEN '#607089'
                    WHEN '#607D8B' THEN '#607089'
                    WHEN '#9E9E9E' THEN '#668E93'
                    ELSE "Color" END;
                    """);
            }
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Sem volta: várias cores antigas viraram a mesma cor nova.
        }
    }
}
