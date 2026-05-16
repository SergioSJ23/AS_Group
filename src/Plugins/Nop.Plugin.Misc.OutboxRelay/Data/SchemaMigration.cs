using FluentMigrator;
using Nop.Data.Extensions;
using Nop.Data.Migrations;
using Nop.Plugin.Misc.OutboxRelay.Domain;

namespace Nop.Plugin.Misc.OutboxRelay.Data;

[NopMigration("2026/06/01 00:00:00:0000000", "Nop.Plugin.Misc.OutboxRelay schema", MigrationProcessType.Installation)]
public class SchemaMigration : Migration
{
    public override void Up()
    {
        this.CreateTableIfNotExists<OutboxMessage>();
    }

    public override void Down()
    {
        this.DeleteTableIfExists<OutboxMessage>();
    }
}
