using FluentMigrator.Builders.Create.Table;
using Nop.Data.Mapping.Builders;
using Nop.Plugin.Misc.OutboxRelay.Domain;

namespace Nop.Plugin.Misc.OutboxRelay.Data;

public class OutboxMessageBuilder : NopEntityBuilder<OutboxMessage>
{
    public override void MapEntity(CreateTableExpressionBuilder table)
    {
        table
            .WithColumn(nameof(OutboxMessage.BuId)).AsString(20).NotNullable()
            .WithColumn(nameof(OutboxMessage.EventType)).AsString(100).NotNullable()
            .WithColumn(nameof(OutboxMessage.Payload)).AsString(int.MaxValue).NotNullable()
            .WithColumn(nameof(OutboxMessage.CreatedAt)).AsDateTime2().NotNullable()
            .WithColumn(nameof(OutboxMessage.PublishedAt)).AsDateTime2().Nullable();
    }
}
