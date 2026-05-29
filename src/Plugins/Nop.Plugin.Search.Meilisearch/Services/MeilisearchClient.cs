using Microsoft.Extensions.Logging;
using Nop.Plugin.Search.Meilisearch.Domain;
using MeiliSdk = Meilisearch;

namespace Nop.Plugin.Search.Meilisearch.Services;

/// <summary>
/// Thin wrapper around the official Meilisearch .NET SDK.
/// One shared index ("products") across both BUs; queries are filtered by buId so each storefront
/// only sees its own catalog. Per-BU isolation is at query time, not at index time.
/// </summary>
public class MeilisearchClient : IMeilisearchClient
{
    private readonly MeiliSdk.MeilisearchClient _sdk;
    private readonly string _buId;
    private readonly ILogger<MeilisearchClient> _logger;

    public MeilisearchClient(string host, string apiKey, string buId, HttpClient httpClient, ILogger<MeilisearchClient> logger)
    {
        httpClient.BaseAddress = new Uri(host.TrimEnd('/') + "/");
        _sdk = new MeiliSdk.MeilisearchClient(httpClient, apiKey);
        _buId = buId;
        _logger = logger;
    }

    public async Task EnsureIndexAsync(CancellationToken ct = default)
    {
        var index = _sdk.Index(MeilisearchDefaults.IndexName);

        MeiliSdk.Index? info = null;
        try
        {
            info = await index.FetchInfoAsync(ct);
        }
        catch
        {
            // Index doesn't exist — create it with the explicit primary key.
        }

        if (info == null)
        {
            var task = await _sdk.CreateIndexAsync(MeilisearchDefaults.IndexName, primaryKey: "id", ct);
            await _sdk.WaitForTaskAsync(task.TaskUid, cancellationToken: ct);
            index = _sdk.Index(MeilisearchDefaults.IndexName);
        }
        else if (info.PrimaryKey == null)
        {
            // Race condition: another BU created the index without a primaryKey.
            // Delete and recreate so BulkIndexAsync can succeed.
            var delTask = await _sdk.DeleteIndexAsync(MeilisearchDefaults.IndexName, ct);
            await _sdk.WaitForTaskAsync(delTask.TaskUid, cancellationToken: ct);
            var createTask = await _sdk.CreateIndexAsync(MeilisearchDefaults.IndexName, primaryKey: "id", ct);
            await _sdk.WaitForTaskAsync(createTask.TaskUid, cancellationToken: ct);
            index = _sdk.Index(MeilisearchDefaults.IndexName);
        }

        var filterTask = await index.UpdateFilterableAttributesAsync(new[] { MeilisearchDefaults.BuIdAttribute }, ct);
        await index.WaitForTaskAsync(filterTask.TaskUid, cancellationToken: ct);
    }

    public async Task<List<int>> SearchProductIdsAsync(string keywords, CancellationToken ct = default)
    {
        var index = _sdk.Index(MeilisearchDefaults.IndexName);

        var query = new MeiliSdk.SearchQuery
        {
            Filter = $"{MeilisearchDefaults.BuIdAttribute} = \"{_buId}\"",
            Limit = 100,
            AttributesToRetrieve = new[] { "productId" }
        };

        var result = await index.SearchAsync<ProductDocument>(keywords ?? string.Empty, query, ct);
        return result.Hits.Select(h => h.ProductId).Where(id => id > 0).ToList();
    }

    public async Task UpsertAsync(IEnumerable<ProductDocument> docs, CancellationToken ct = default)
    {
        var batch = docs.ToList();
        if (batch.Count == 0)
            return;

        var index = _sdk.Index(MeilisearchDefaults.IndexName);
        var task = await index.AddDocumentsAsync(batch, primaryKey: "id", ct);
        _logger.LogDebug("Meilisearch upsert: {Count} docs queued as task {TaskUid}", batch.Count, task.TaskUid);
    }

    public async Task DeleteAsync(string documentId, CancellationToken ct = default)
    {
        var index = _sdk.Index(MeilisearchDefaults.IndexName);
        await index.DeleteOneDocumentAsync(documentId, ct);
    }

    public async Task<bool> HealthAsync(CancellationToken ct = default)
    {
        try
        {
            return await _sdk.IsHealthyAsync();
        }
        catch
        {
            return false;
        }
    }
}
