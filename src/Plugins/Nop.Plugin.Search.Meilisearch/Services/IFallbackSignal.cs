namespace Nop.Plugin.Search.Meilisearch.Services;

/// <summary>
/// Per-request flag that is raised when the Meilisearch call throws, before nopCommerce's
/// ProductService.SearchProductsAsync swallows the exception and falls back to DB search.
/// The fallback banner ViewComponent reads this on the same request to decide whether to render.
/// </summary>
public interface IFallbackSignal
{
    bool TriggeredThisRequest { get; }

    void Trigger();
}
