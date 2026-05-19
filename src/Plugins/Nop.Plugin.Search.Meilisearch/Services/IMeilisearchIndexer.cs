using Nop.Core.Domain.Catalog;

namespace Nop.Plugin.Search.Meilisearch.Services;

public interface IMeilisearchIndexer
{
    /// <summary>
    /// Index all published, non-deleted products from this BU's local DB.
    /// Called once at plugin install — afterwards the entity event consumer keeps the index in sync.
    /// </summary>
    Task BulkIndexAsync(CancellationToken ct = default);

    /// <summary>
    /// Upsert a single product into the shared index (tagged with this BU's buId).
    /// </summary>
    Task UpsertAsync(Product product, CancellationToken ct = default);

    /// <summary>
    /// Delete this BU's document for the given product from the shared index.
    /// </summary>
    Task DeleteAsync(int productId, CancellationToken ct = default);
}
