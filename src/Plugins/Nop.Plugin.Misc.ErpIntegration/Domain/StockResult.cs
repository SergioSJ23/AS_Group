namespace Nop.Plugin.Misc.ErpIntegration.Domain;

public record StockResult(int Quantity, bool IsStale, string Source);
