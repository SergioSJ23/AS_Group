using Microsoft.AspNetCore.Mvc;
using Nop.Plugin.Misc.ErpIntegration.Services;
using Nop.Web.Framework.Components;
using Nop.Web.Models.Catalog;

namespace Nop.Plugin.Misc.ErpIntegration.Components;

public class ErpStockBannerViewComponent : NopViewComponent
{
    private readonly IErpStockService _erpStock;

    public ErpStockBannerViewComponent(IErpStockService erpStock)
    {
        _erpStock = erpStock;
    }

    public async Task<IViewComponentResult> InvokeAsync(string widgetZone, object additionalData)
    {
        if (additionalData is not ProductDetailsModel model || string.IsNullOrEmpty(model.Sku))
            return Content(string.Empty);

        var stock = await _erpStock.GetStockAsync(model.Sku);
        return await ViewAsync("~/Plugins/Misc.ErpIntegration/Views/PublicInfo.cshtml", stock);
    }
}
