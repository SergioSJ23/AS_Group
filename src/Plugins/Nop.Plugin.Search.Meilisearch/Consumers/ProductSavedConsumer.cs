using Microsoft.Extensions.Logging;
using Nop.Core.Domain.Catalog;
using Nop.Core.Events;
using Nop.Plugin.Search.Meilisearch.Services;
using Nop.Services.Events;

namespace Nop.Plugin.Search.Meilisearch.Consumers;

/// <summary>
/// Keeps the Meilisearch index in sync with product changes after the bulk seed at install time.
/// Failures are logged but never rethrown so a Meilisearch outage cannot break product CRUD in the admin.
/// </summary>
public class ProductSavedConsumer :
    IConsumer<EntityInsertedEvent<Product>>,
    IConsumer<EntityUpdatedEvent<Product>>,
    IConsumer<EntityDeletedEvent<Product>>
{
    private readonly IMeilisearchIndexer _indexer;
    private readonly ILogger<ProductSavedConsumer> _logger;

    public ProductSavedConsumer(IMeilisearchIndexer indexer, ILogger<ProductSavedConsumer> logger)
    {
        _indexer = indexer;
        _logger = logger;
    }

    public Task HandleEventAsync(EntityInsertedEvent<Product> eventMessage)
        => SafeUpsert(eventMessage.Entity);

    public Task HandleEventAsync(EntityUpdatedEvent<Product> eventMessage)
        => SafeUpsert(eventMessage.Entity);

    public async Task HandleEventAsync(EntityDeletedEvent<Product> eventMessage)
    {
        try
        {
            await _indexer.DeleteAsync(eventMessage.Entity.Id);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Meilisearch delete failed for product {ProductId}", eventMessage.Entity.Id);
        }
    }

    private async Task SafeUpsert(Product product)
    {
        try
        {
            await _indexer.UpsertAsync(product);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Meilisearch upsert failed for product {ProductId}", product.Id);
        }
    }
}
