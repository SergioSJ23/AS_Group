using Nop.Plugin.Misc.ErpIntegration.Domain;

namespace Nop.Plugin.Misc.ErpIntegration.Services;

public interface IErpStockService
{
    Task<StockResult> GetStockAsync(string sku, CancellationToken ct = default);
}
