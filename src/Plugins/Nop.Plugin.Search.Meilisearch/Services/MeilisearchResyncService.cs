using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Nop.Data;

namespace Nop.Plugin.Search.Meilisearch.Services;

/// <summary>
/// Closes the QA4 recovery gap: product changes that happen while Meilisearch is unreachable flow
/// through nopCommerce's in-process event bus and never reach the (down) index. Without this service
/// the index stays stale after recovery until the next product edit.
///
/// This hosted service probes Meilisearch health on a fixed interval and, on a down → up transition,
/// triggers a full bulk reindex of this BU's catalog. Because the probe interval is well under the
/// QA4 budget, "resync completes within 5 minutes of recovery" holds: detection takes at most one
/// probe interval and the reindex itself is seconds for a per-BU catalog.
/// </summary>
public class MeilisearchResyncService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly IMeilisearchClient _client;
    private readonly ILogger<MeilisearchResyncService> _logger;

    private static readonly TimeSpan ProbeInterval = TimeSpan.FromSeconds(30);

    // Start optimistic: a normal boot (Meilisearch already healthy) must NOT trigger a reindex —
    // InstallAsync already does the initial bulk index. Only an observed outage that then recovers
    // counts as a down → up transition worth resyncing.
    private bool _lastHealthy = true;

    public MeilisearchResyncService(
        IServiceScopeFactory scopeFactory,
        IMeilisearchClient client,
        ILogger<MeilisearchResyncService> logger)
    {
        _scopeFactory = scopeFactory;
        _client = client;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var healthy = await _client.HealthAsync(stoppingToken);

                if (healthy && !_lastHealthy && DataSettingsManager.IsDatabaseInstalled())
                {
                    _logger.LogInformation("Meilisearch recovered — triggering bulk reindex to resync the index");
                    using var scope = _scopeFactory.CreateScope();
                    var indexer = scope.ServiceProvider.GetRequiredService<IMeilisearchIndexer>();
                    await indexer.BulkIndexAsync(stoppingToken);
                    SearchMetrics.ResyncTotal.Add(1);
                    _logger.LogInformation("Meilisearch resync complete");
                }
                else if (!healthy && _lastHealthy)
                {
                    _logger.LogWarning("Meilisearch health probe failed — index considered stale until recovery");
                }

                _lastHealthy = healthy;
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Meilisearch resync probe failed");
            }

            try
            {
                await Task.Delay(ProbeInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }
    }
}
