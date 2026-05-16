using System.Net.Http.Json;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Nop.Plugin.Misc.ErpIntegration.Domain;

namespace Nop.Plugin.Misc.ErpIntegration.Services;

public class ErpStockService : IErpStockService
{
    private readonly IHttpClientFactory _httpFactory;
    private readonly IMemoryCache _cache;
    private readonly ErpCircuitBreaker _breaker;
    private readonly ILogger<ErpStockService> _logger;

    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(5);

    public ErpStockService(
        IHttpClientFactory httpFactory,
        IMemoryCache cache,
        ErpCircuitBreaker breaker,
        ILogger<ErpStockService> logger)
    {
        _httpFactory = httpFactory;
        _cache = cache;
        _breaker = breaker;
        _logger = logger;
    }

    public async Task<StockResult> GetStockAsync(string sku, CancellationToken ct = default)
    {
        if (string.IsNullOrEmpty(sku))
            return new StockResult(0, IsStale: false, Source: "no-sku");

        var cacheKey = $"erp.stock.{sku}";

        if (_breaker.IsOpen)
        {
            _logger.LogDebug("ERP circuit OPEN — returning cached stock for {Sku}", sku);
            return _cache.TryGetValue(cacheKey, out int cached)
                ? new StockResult(cached, IsStale: true, Source: "cache")
                : new StockResult(0, IsStale: true, Source: "cache-miss");
        }

        try
        {
            var client = _httpFactory.CreateClient("erp");
            var resp = await client.GetAsync($"/stock/{sku}", ct);
            resp.EnsureSuccessStatusCode();

            var data = await resp.Content.ReadFromJsonAsync<ErpStockData>(cancellationToken: ct)
                       ?? throw new InvalidOperationException("Empty ERP response");

            _cache.Set(cacheKey, data.Quantity, CacheTtl);
            _breaker.RecordSuccess();
            return new StockResult(data.Quantity, IsStale: false, Source: "live");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "ERP call failed for {Sku} — circuit state: {State}", sku, _breaker.CurrentState);
            _breaker.RecordFailure();
            return _cache.TryGetValue(cacheKey, out int cached)
                ? new StockResult(cached, IsStale: true, Source: "cache")
                : new StockResult(0, IsStale: true, Source: "fallback");
        }
    }

    private record ErpStockData(string Sku, int Quantity, string WarehouseId);
}
