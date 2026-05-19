namespace Nop.Plugin.Search.Meilisearch;

public static class MeilisearchDefaults
{
    public const string SystemName = "Search.Meilisearch";

    public const string IndexName = "products";

    public const string BuIdAttribute = "buId";

    public static readonly TimeSpan SearchTimeout = TimeSpan.FromMilliseconds(1500);
}
