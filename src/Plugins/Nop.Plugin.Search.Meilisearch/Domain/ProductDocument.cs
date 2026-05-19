using System.Text.Json.Serialization;

namespace Nop.Plugin.Search.Meilisearch.Domain;

/// <summary>
/// Shape of a single document in the shared Meilisearch "products" index.
/// Each BU writes its own products with its buId tag; queries filter by buId at read time.
/// </summary>
public class ProductDocument
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("productId")]
    public int ProductId { get; set; }

    [JsonPropertyName("buId")]
    public string BuId { get; set; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; set; } = string.Empty;

    [JsonPropertyName("description")]
    public string Description { get; set; } = string.Empty;

    [JsonPropertyName("sku")]
    public string Sku { get; set; } = string.Empty;

    public static string BuildId(string buId, int productId) => $"{buId}-{productId}";
}
