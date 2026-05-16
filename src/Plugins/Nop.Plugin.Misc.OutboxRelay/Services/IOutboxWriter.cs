namespace Nop.Plugin.Misc.OutboxRelay.Services;

public interface IOutboxWriter
{
    Task WriteAsync(string eventType, object payload);
}
