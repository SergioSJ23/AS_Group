using Microsoft.Extensions.Logging;
using Nop.Core.Domain.Catalog;
using Nop.Core.Domain.Seo;
using Nop.Data;
using Nop.Plugin.Search.Meilisearch.Domain;
using Nop.Services.Media;

namespace Nop.Plugin.Search.Meilisearch.Services;

public class MeilisearchIndexer : IMeilisearchIndexer
{
    private readonly IMeilisearchClient _client;
    private readonly IRepository<Product> _productRepository;
    private readonly IRepository<UrlRecord> _urlRecordRepository;
    private readonly IRepository<ProductPicture> _productPictureRepository;
    private readonly IPictureService _pictureService;
    private readonly string _buId;
    private readonly ILogger<MeilisearchIndexer> _logger;

    private const int BatchSize = 500;
    private const int ThumbSize = 300;

    public MeilisearchIndexer(
        IMeilisearchClient client,
        IRepository<Product> productRepository,
        IRepository<UrlRecord> urlRecordRepository,
        IRepository<ProductPicture> productPictureRepository,
        IPictureService pictureService,
        string buId,
        ILogger<MeilisearchIndexer> logger)
    {
        _client = client;
        _productRepository = productRepository;
        _urlRecordRepository = urlRecordRepository;
        _productPictureRepository = productPictureRepository;
        _pictureService = pictureService;
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

        // First picture (lowest DisplayOrder) per product
        var firstPictureIdByProduct = _productPictureRepository.Table
            .Where(pp => productIds.Contains(pp.ProductId))
            .GroupBy(pp => pp.ProductId)
            .Select(g => new { ProductId = g.Key, PictureId = g.OrderBy(pp => pp.DisplayOrder).First().PictureId })
            .ToDictionary(x => x.ProductId, x => x.PictureId);

        // Resolve picture URLs (async, done outside the batch loop)
        var pictureUrls = new Dictionary<int, string>();
        foreach (var (productId, pictureId) in firstPictureIdByProduct)
        {
            pictureUrls[productId] = await _pictureService.GetPictureUrlAsync(pictureId, ThumbSize);
        }

        for (var offset = 0; offset < products.Count; offset += BatchSize)
        {
            var batch = products.Skip(offset).Take(BatchSize).Select(p => new ProductDocument
            {
                Id = ProductDocument.BuildId(_buId, p.Id),
                ProductId = p.Id,
                BuId = _buId,
                Name = p.Name ?? string.Empty,
                Description = p.ShortDescription ?? string.Empty,
                Sku = p.Sku ?? string.Empty,
                Slug = slugsByProductId.GetValueOrDefault(p.Id, string.Empty),
                Price = p.Price,
                PictureUrl = pictureUrls.GetValueOrDefault(p.Id, string.Empty)
            });
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

        var pictureId = _productPictureRepository.Table
            .Where(pp => pp.ProductId == product.Id)
            .OrderBy(pp => pp.DisplayOrder)
            .Select(pp => pp.PictureId)
            .FirstOrDefault();

        var pictureUrl = pictureId > 0
            ? await _pictureService.GetPictureUrlAsync(pictureId, ThumbSize)
            : string.Empty;

        await _client.UpsertAsync(new[] { new ProductDocument
        {
            Id = ProductDocument.BuildId(_buId, product.Id),
            ProductId = product.Id,
            BuId = _buId,
            Name = product.Name ?? string.Empty,
            Description = product.ShortDescription ?? string.Empty,
            Sku = product.Sku ?? string.Empty,
            Slug = slug,
            Price = product.Price,
            PictureUrl = pictureUrl
        }}, ct);
    }

    public Task DeleteAsync(int productId, CancellationToken ct = default)
        => _client.DeleteAsync(ProductDocument.BuildId(_buId, productId), ct);
}
