using Nop.Plugin.Search.Meilisearch.Domain;

namespace Nop.Plugin.Search.Meilisearch.Services;

public interface IMeilisearchClient
{
    Task EnsureIndexAsync(CancellationToken ct = default);

    Task<List<int>> SearchProductIdsAsync(string keywords, CancellationToken ct = default);

    Task UpsertAsync(IEnumerable<ProductDocument> docs, CancellationToken ct = default);

    Task DeleteAsync(string documentId, CancellationToken ct = default);

    Task<bool> HealthAsync(CancellationToken ct = default);
}
