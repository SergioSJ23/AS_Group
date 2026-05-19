namespace Nop.Plugin.Search.Meilisearch.Services;

public class FallbackSignal : IFallbackSignal
{
    public bool TriggeredThisRequest { get; private set; }

    public void Trigger() => TriggeredThisRequest = true;
}
