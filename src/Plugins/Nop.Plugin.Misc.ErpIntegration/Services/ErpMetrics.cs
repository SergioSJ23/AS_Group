using System.Diagnostics.Metrics;

namespace Nop.Plugin.Misc.ErpIntegration.Services;

internal static class ErpMetrics
{
    public const string MeterName = "Northstar.Erp";

    private static readonly Meter _meter = new(MeterName, "1.0.0");

    // 0 = CLOSED, 1 = HALF-OPEN, 2 = OPEN. Single int suffices because the breaker is per-process.
    private static int _currentState;

    public static readonly ObservableGauge<int> BreakerState =
        _meter.CreateObservableGauge("erp_breaker_state", () => _currentState,
            description: "Current ERP circuit breaker state: 0=closed, 1=half-open, 2=open.");

    public static readonly Counter<long> BreakerTransitions =
        _meter.CreateCounter<long>("erp_breaker_transitions_total",
            description: "Circuit breaker state transitions, tagged with the new state.");

    public static readonly Histogram<double> CallDurationMs =
        _meter.CreateHistogram<double>("erp_call_duration_ms", "ms",
            "Time spent in IErpStockService.GetStockAsync, tagged by outcome (live/cache/cache-miss/short-circuit).");

    public static readonly Counter<long> CacheServeTotal =
        _meter.CreateCounter<long>("erp_cache_serve_total",
            description: "Stock reads served from cache (breaker open) instead of the live ERP.");

    public static void RecordTransition(string toState)
    {
        _currentState = toState switch
        {
            "CLOSED" => 0,
            "HALFOPEN" => 1,
            "OPEN" => 2,
            _ => _currentState
        };
        BreakerTransitions.Add(1, new KeyValuePair<string, object?>("state", toState.ToLowerInvariant()));
    }
}
