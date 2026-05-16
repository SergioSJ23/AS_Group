using System.Text.Json.Serialization;

namespace EspoCrmConsumer;

public record OrderMessage(
    [property: JsonPropertyName("orderId")] int OrderId,
    [property: JsonPropertyName("orderGuid")] Guid OrderGuid,
    [property: JsonPropertyName("customerId")] int CustomerId,
    [property: JsonPropertyName("customerEmail")] string CustomerEmail,
    [property: JsonPropertyName("orderTotal")] decimal OrderTotal,
    [property: JsonPropertyName("buId")] string BuId,
    [property: JsonPropertyName("timestamp")] DateTime Timestamp
);
