using Microsoft.Extensions.Logging;
using Nop.Core.Domain.Catalog;
using Nop.Core.Domain.Cms;
using Nop.Plugin.Search.Meilisearch.Components;
using Nop.Plugin.Search.Meilisearch.Services;
using Nop.Services.Catalog;
using Nop.Services.Cms;
using Nop.Services.Configuration;
using Nop.Services.Plugins;
using Nop.Web.Framework.Infrastructure;

namespace Nop.Plugin.Search.Meilisearch;

/// <summary>
/// nopCommerce-side entry point for the Meilisearch federated search plugin.
///
/// Failure model: any exception thrown from <see cref="SearchProductsAsync"/> is caught by
/// ProductService.SearchProductsAsync (built into nopCommerce when
/// CatalogSettings.UseStandardSearchWhenSearchProviderThrowsException is true), which then runs
/// the standard DB search. We raise <see cref="IFallbackSignal"/> before re-throwing so a
/// downstream widget can render a "degraded results" banner on the same request.
/// </summary>
public class MeilisearchSearchProvider : BasePlugin, ISearchProvider, IWidgetPlugin
{
    private readonly IMeilisearchClient _meilisearchClient;
    private readonly IMeilisearchIndexer _indexer;
    private readonly IFallbackSignal _fallbackSignal;
    private readonly ISettingService _settingService;
    private readonly CatalogSettings _catalogSettings;
    private readonly WidgetSettings _widgetSettings;
    private readonly ILogger<MeilisearchSearchProvider> _logger;

    public MeilisearchSearchProvider(
        IMeilisearchClient meilisearchClient,
        IMeilisearchIndexer indexer,
        IFallbackSignal fallbackSignal,
        ISettingService settingService,
        CatalogSettings catalogSettings,
        WidgetSettings widgetSettings,
        ILogger<MeilisearchSearchProvider> logger)
    {
        _meilisearchClient = meilisearchClient;
        _indexer = indexer;
        _fallbackSignal = fallbackSignal;
        _settingService = settingService;
        _catalogSettings = catalogSettings;
        _widgetSettings = widgetSettings;
        _logger = logger;
    }

    public async Task<List<int>> SearchProductsAsync(string keywords, bool isLocalized)
    {
        using var cts = new CancellationTokenSource(MeilisearchDefaults.SearchTimeout);
        try
        {
            return await _meilisearchClient.SearchProductIdsAsync(keywords, cts.Token);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Meilisearch query failed — raising fallback signal so DB search takes over");
            _fallbackSignal.Trigger();
            throw;
        }
    }

    public Task<IList<string>> GetWidgetZonesAsync()
        => Task.FromResult<IList<string>>(new List<string>
        {
            PublicWidgetZones.ProductSearchPageBeforeResults
        });

    public Type GetWidgetViewComponent(string widgetZone)
        => typeof(SearchFallbackBannerViewComponent);

    public bool HideInWidgetList => true;

    public override string GetConfigurationPageUrl() => string.Empty;

    public override async Task InstallAsync()
    {
        _catalogSettings.ActiveSearchProviderSystemName = MeilisearchDefaults.SystemName;
        _catalogSettings.UseStandardSearchWhenSearchProviderThrowsException = true;
        await _settingService.SaveSettingAsync(_catalogSettings);

        if (!_widgetSettings.ActiveWidgetSystemNames.Contains(MeilisearchDefaults.SystemName))
        {
            _widgetSettings.ActiveWidgetSystemNames.Add(MeilisearchDefaults.SystemName);
            await _settingService.SaveSettingAsync(_widgetSettings);
        }

        try
        {
            await _indexer.BulkIndexAsync();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Bulk index at install failed — entity event consumer will catch up as products change");
        }

        await base.InstallAsync();
    }

    public override async Task UninstallAsync()
    {
        if (string.Equals(_catalogSettings.ActiveSearchProviderSystemName, MeilisearchDefaults.SystemName, StringComparison.Ordinal))
        {
            _catalogSettings.ActiveSearchProviderSystemName = string.Empty;
            await _settingService.SaveSettingAsync(_catalogSettings);
        }

        if (_widgetSettings.ActiveWidgetSystemNames.Contains(MeilisearchDefaults.SystemName))
        {
            _widgetSettings.ActiveWidgetSystemNames.Remove(MeilisearchDefaults.SystemName);
            await _settingService.SaveSettingAsync(_widgetSettings);
        }

        await base.UninstallAsync();
    }
}
