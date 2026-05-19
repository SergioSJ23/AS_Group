using Microsoft.AspNetCore.Mvc;
using Nop.Plugin.Search.Meilisearch.Services;
using Nop.Web.Framework.Components;

namespace Nop.Plugin.Search.Meilisearch.Components;

/// <summary>
/// Renders the "degraded results" banner on the product search page when the request has
/// already raised <see cref="IFallbackSignal"/> earlier in its lifetime (typically inside
/// <c>MeilisearchSearchProvider.SearchProductsAsync</c>).
/// </summary>
public class SearchFallbackBannerViewComponent : NopViewComponent
{
    private readonly IFallbackSignal _fallbackSignal;

    public SearchFallbackBannerViewComponent(IFallbackSignal fallbackSignal)
    {
        _fallbackSignal = fallbackSignal;
    }

    public IViewComponentResult Invoke(string widgetZone, object additionalData)
    {
        if (!_fallbackSignal.TriggeredThisRequest)
            return Content(string.Empty);

        return View("~/Plugins/Search.Meilisearch/Views/SearchFallbackBanner.cshtml");
    }
}
