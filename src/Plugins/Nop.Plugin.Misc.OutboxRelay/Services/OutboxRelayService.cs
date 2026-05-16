using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Nop.Data;
using Nop.Plugin.Misc.OutboxRelay.Domain;

namespace Nop.Plugin.Misc.OutboxRelay.Services;

public class OutboxRelayService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly RabbitMqPublisher _publisher;
    private readonly ILogger<OutboxRelayService> _logger;

    public OutboxRelayService(
        IServiceScopeFactory scopeFactory,
        RabbitMqPublisher publisher,
        ILogger<OutboxRelayService> logger)
    {
        _scopeFactory = scopeFactory;
        _publisher = publisher;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (DataSettingsManager.IsDatabaseInstalled())
                    await RelayPendingAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "Outbox relay cycle failed");
            }

            await Task.Delay(5_000, stoppingToken);
        }
    }

    private async Task RelayPendingAsync(CancellationToken cancellationToken)
    {
        using var scope = _scopeFactory.CreateScope();
        var repository = scope.ServiceProvider.GetRequiredService<IRepository<OutboxMessage>>();

        var pending = await repository.GetAllAsync(q =>
            q.Where(m => !m.PublishedAt.HasValue)
             .OrderBy(m => m.CreatedAt)
             .Take(50));

        if (pending.Count == 0)
            return;

        var published = new List<OutboxMessage>(pending.Count);
        foreach (var message in pending)
        {
            if (cancellationToken.IsCancellationRequested) break;
            try
            {
                var routingKey = $"{message.BuId}.order.placed";
                await _publisher.PublishAsync(routingKey, message.Payload, cancellationToken);
                message.PublishedAt = DateTime.UtcNow;
                published.Add(message);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to publish outbox message {Id}, will retry", message.Id);
            }
        }

        if (published.Count > 0)
            await repository.UpdateAsync(published);
    }
}
