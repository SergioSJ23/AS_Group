using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Nop.Core.Domain.Catalog;
using Nop.Core.Domain.Seo;
using Nop.Core.Infrastructure;
using Nop.Data;
using Nop.Plugin.Search.Meilisearch.Services;
using Nop.Services.Media;

namespace Nop.Plugin.Search.Meilisearch.Infrastructure;

public class PluginNopStartup : INopStartup
{
    public void ConfigureServices(IServiceCollection services, IConfiguration configuration)
    {
        var host = configuration["MEILISEARCH_URI"]
            ?? Environment.GetEnvironmentVariable("MEILISEARCH_URI")
            ?? "http://meilisearch:7700";
        var apiKey = configuration["MEILISEARCH_KEY"]
            ?? Environment.GetEnvironmentVariable("MEILISEARCH_KEY")
            ?? string.Empty;
        var buId = configuration["BU_ID"]
            ?? Environment.GetEnvironmentVariable("BU_ID")
            ?? "unknown";

        // Generous HttpClient timeout (covers bulk index calls); fast-fail for search is enforced
        // per-call inside MeilisearchSearchProvider via a 1.5s CancellationTokenSource.
        services.AddHttpClient("meilisearch", c =>
        {
            c.Timeout = TimeSpan.FromSeconds(30);
        });

        services.AddSingleton<IMeilisearchClient>(sp =>
        {
            var http = sp.GetRequiredService<IHttpClientFactory>().CreateClient("meilisearch");
            var logger = sp.GetRequiredService<ILogger<MeilisearchClient>>();
            return new MeilisearchClient(host, apiKey, buId, http, logger);
        });

        services.AddScoped<IMeilisearchIndexer>(sp => new MeilisearchIndexer(
            sp.GetRequiredService<IMeilisearchClient>(),
            sp.GetRequiredService<IRepository<Product>>(),
            sp.GetRequiredService<IRepository<UrlRecord>>(),
            sp.GetRequiredService<IRepository<ProductPicture>>(),
            sp.GetRequiredService<IPictureService>(),
            buId,
            sp.GetRequiredService<ILogger<MeilisearchIndexer>>()));

        services.AddScoped<IFallbackSignal, FallbackSignal>();

        // Auto-resync the index after a Meilisearch outage (QA4: resync within 5 minutes of recovery).
        services.AddHostedService<MeilisearchResyncService>();
    }

    public void Configure(IApplicationBuilder application) { }

    public int Order => 3200;
}
