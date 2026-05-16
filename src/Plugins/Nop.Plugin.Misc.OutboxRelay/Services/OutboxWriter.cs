using System.Text.Json;
using Nop.Data;
using Nop.Plugin.Misc.OutboxRelay.Domain;

namespace Nop.Plugin.Misc.OutboxRelay.Services;

// Inserts an OutboxMessage using the same IRepository<T> scope as the order insert,
// keeping both writes within the same EF Core DbContext unit of work.
public class OutboxWriter : IOutboxWriter
{
    private readonly IRepository<OutboxMessage> _repository;

    public OutboxWriter(IRepository<OutboxMessage> repository)
    {
        _repository = repository;
    }

    public async Task WriteAsync(string eventType, object payload)
    {
        var message = new OutboxMessage
        {
            BuId = Environment.GetEnvironmentVariable("BU_ID") ?? "unknown",
            EventType = eventType,
            Payload = JsonSerializer.Serialize(payload),
            CreatedAt = DateTime.UtcNow
        };
        await _repository.InsertAsync(message);
    }
}
