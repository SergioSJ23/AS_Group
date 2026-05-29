using System.Diagnostics.Metrics;

namespace EspoCrmConsumer;

internal static class CrmConsumerMetrics
{
    public const string MeterName = "Northstar.CrmConsumer";

    private static readonly Meter _meter = new(MeterName, "1.0.0");

    public static readonly Counter<long> ProcessedTotal =
        _meter.CreateCounter<long>("crm_messages_processed_total",
            description: "Order messages successfully written to EspoCRM.");

    public static readonly Counter<long> FailedTotal =
        _meter.CreateCounter<long>("crm_messages_failed_total",
            description: "Order messages that failed processing and were routed to DLQ.");

    public static readonly Counter<long> DuplicateTotal =
        _meter.CreateCounter<long>("crm_messages_duplicate_total",
            description: "Duplicate order messages skipped by idempotency guard.");
}
