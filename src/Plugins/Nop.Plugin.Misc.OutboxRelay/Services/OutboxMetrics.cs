using System.Diagnostics.Metrics;

namespace Nop.Plugin.Misc.OutboxRelay.Services;

internal static class OutboxMetrics
{
    public const string MeterName = "Northstar.OutboxRelay";

    private static readonly Meter _meter = new(MeterName, "1.0.0");

    // Updated at the start of each relay cycle; observed via the gauge below.
    // ObservableGauge calls back at scrape time so the value is always fresh-ish (≤ cycle interval).
    private static long _lastUnpublishedCount;

    public static readonly ObservableGauge<long> UnpublishedRows =
        _meter.CreateObservableGauge("outbox_unpublished_rows", () => _lastUnpublishedCount,
            description: "Outbox messages still pending publish to RabbitMQ, sampled at last relay cycle.");

    public static readonly Histogram<double> PublishLatencyMs =
        _meter.CreateHistogram<double>("outbox_publish_latency_ms", "ms",
            "Time from CreatedAt to PublishedAt for an outbox row.");

    public static readonly Counter<long> PublishedTotal =
        _meter.CreateCounter<long>("outbox_published_total", description: "Outbox rows successfully relayed to RabbitMQ.");

    public static readonly Counter<long> PublishFailureTotal =
        _meter.CreateCounter<long>("outbox_publish_failures_total", description: "Outbox publish attempts that threw an exception.");

    public static void SetUnpublishedCount(long count) => _lastUnpublishedCount = count;
}
