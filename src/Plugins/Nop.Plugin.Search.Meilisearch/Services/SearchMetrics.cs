using System.Diagnostics.Metrics;

namespace Nop.Plugin.Search.Meilisearch.Services;

internal static class SearchMetrics
{
    public const string MeterName = "Northstar.Search";

    private static readonly Meter _meter = new(MeterName, "1.0.0");

    public static readonly Histogram<double> SearchDurationMs =
        _meter.CreateHistogram<double>("search_duration_ms", "ms", "Time spent serving a product search, tagged by backend (meili/error).");

    public static readonly Counter<long> SearchFallbackTotal =
        _meter.CreateCounter<long>("search_fallback_total", description: "Searches that threw and triggered nopCommerce's DB fallback path.");
}
