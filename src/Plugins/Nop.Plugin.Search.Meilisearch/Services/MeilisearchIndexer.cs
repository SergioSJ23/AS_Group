using Microsoft.Extensions.Logging;
using Nop.Core.Domain.Catalog;
using Nop.Core.Domain.Seo;
using Nop.Data;
using Nop.Plugin.Search.Meilisearch.Domain;

namespace Nop.Plugin.Search.Meilisearch.Services;

public class MeilisearchIndexer : IMeilisearchIndexer
{
    private readonly IMeilisearchClient _client;
    private readonly IRepository<Product> _productRepository;
    private readonly IRepository<UrlRecord> _urlRecordRepository;
    private readonly string _buId;
    private readonly ILogger<MeilisearchIndexer> _logger;

    private const int BatchSize = 500;

    public MeilisearchIndexer(
        IMeilisearchClient client,
        IRepository<Product> productRepository,
        IRepository<UrlRecord> urlRecordRepository,
        string buId,
        ILogger<MeilisearchIndexer> logger)
    {
        _client = client;
        _productRepository = productRepository;
        _urlRecordRepository = urlRecordRepository;
        _buId = buId;
        _logger = logger;
    }

    public async Task BulkIndexAsync(CancellationToken ct = default)
    {
        await _client.EnsureIndexAsync(ct);

        var products = _productRepository.Table
            .Where(p => !p.Deleted && p.Published)
            .ToList();

        _logger.LogInformation("Bulk indexing {Count} products for BU {BuId}", products.Count, _buId);

        var productIds = products.Select(p => p.Id).ToHashSet();
        var slugsByProductId = _urlRecordRepository.Table
            .Where(ur => ur.EntityName == "Product" && ur.IsActive && productIds.Contains(ur.EntityId))
            .ToDictionary(ur => ur.EntityId, ur => ur.Slug);

        for (var offset = 0; offset < products.Count; offset += BatchSize)
        {
            var batch = products.Skip(offset).Take(BatchSize)
                .Select(p => ToDocument(p, slugsByProductId.GetValueOrDefault(p.Id, string.Empty)));
            await _client.UpsertAsync(batch, ct);
        }
    }

    public async Task UpsertAsync(Product product, CancellationToken ct = default)
    {
        if (product is null || product.Deleted)
            return;

        if (!product.Published)
        {
            await DeleteAsync(product.Id, ct);
            return;
        }

        var slug = _urlRecordRepository.Table
            .Where(ur => ur.EntityName == "Product" && ur.IsActive && ur.EntityId == product.Id)
            .Select(ur => ur.Slug)
            .FirstOrDefault() ?? string.Empty;

        await _client.UpsertAsync(new[] { ToDocument(product, slug) }, ct);
    }

    public Task DeleteAsync(int productId, CancellationToken ct = default)
        => _client.DeleteAsync(ProductDocument.BuildId(_buId, productId), ct);

    private ProductDocument ToDocument(Product p, string slug) => new()
    {
        Id = ProductDocument.BuildId(_buId, p.Id),
        ProductId = p.Id,
        BuId = _buId,
        Name = p.Name ?? string.Empty,
        Description = p.ShortDescription ?? string.Empty,
        Sku = p.Sku ?? string.Empty,
        Slug = slug,
        Price = p.Price
    };
}
