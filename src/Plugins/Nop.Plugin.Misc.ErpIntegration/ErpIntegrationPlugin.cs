using Nop.Plugin.Misc.ErpIntegration.Components;
using Nop.Services.Cms;
using Nop.Services.Common;
using Nop.Services.Plugins;
using Nop.Web.Framework.Infrastructure;

namespace Nop.Plugin.Misc.ErpIntegration;

public class ErpIntegrationPlugin : BasePlugin, IWidgetPlugin
{
    public Task<IList<string>> GetWidgetZonesAsync()
        => Task.FromResult<IList<string>>(new List<string>
        {
            PublicWidgetZones.ProductDetailsOverviewTop
        });

    public Type GetWidgetViewComponent(string widgetZone)
        => typeof(ErpStockBannerViewComponent);

    public override string GetConfigurationPageUrl() => string.Empty;

    public bool HideInWidgetList => false;
}
