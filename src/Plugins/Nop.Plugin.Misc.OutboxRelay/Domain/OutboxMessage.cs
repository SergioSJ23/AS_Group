using Nop.Core;

namespace Nop.Plugin.Misc.OutboxRelay.Domain;

public class OutboxMessage : BaseEntity
{
    public string BuId { get; set; } = string.Empty;
    public string EventType { get; set; } = string.Empty;
    public string Payload { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public DateTime? PublishedAt { get; set; }
}
