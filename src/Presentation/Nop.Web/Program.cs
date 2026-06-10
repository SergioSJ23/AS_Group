using Autofac.Extensions.DependencyInjection;
using Nop.Core.Configuration;
using Nop.Core.Infrastructure;
using Nop.Web.Framework.Infrastructure.Extensions;
using OpenTelemetry.Metrics;

namespace Nop.Web;

public partial class Program
{
    // Dedicated port for the Prometheus scrape endpoint. Kept separate from the
    // storefront port (80) so /metrics is served by a branched pipeline that does
    // NOT run the DB-bound nopCommerce middleware. This keeps metrics responsive
    // even when this BU's database is down (ADR-001 isolation demo), where the
    // main pipeline would otherwise fail. Both BU containers listen on this same
    // internal port; Prometheus scrapes nop_bu1:9101 / nop_bu2:9101.
    private const int MetricsPort = 9101;

    public static async Task Main(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);

        builder.Configuration.AddJsonFile(NopConfigurationDefaults.AppSettingsFilePath, true, true);
        if (!string.IsNullOrEmpty(builder.Environment?.EnvironmentName))
        {
            var path = string.Format(NopConfigurationDefaults.AppSettingsEnvironmentFilePath, builder.Environment.EnvironmentName);
            builder.Configuration.AddJsonFile(path, true, true);
        }
        builder.Configuration.AddEnvironmentVariables();

        //load application settings
        builder.Services.ConfigureApplicationSettings(builder);

        var appSettings = Singleton<AppSettings>.Instance;
        var useAutofac = appSettings.Get<CommonConfig>().UseAutofac;

        if (useAutofac)
            builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());
        else
        {
            builder.Host.UseDefaultServiceProvider(options =>
            {
                //we don't validate the scopes, since at the app start and the initial configuration we need 
                //to resolve some services (registered as "scoped") through the root container
                options.ValidateScopes = false;
                options.ValidateOnBuild = true;
            });
        }

        //add services to the application and configure service provider
        builder.Services.ConfigureApplicationServices(builder);

        // OpenTelemetry: register before Build() so plugin Meters are discovered at startup.
        // "Northstar.*" wildcard picks up every meter declared in the OutboxRelay,
        // ErpIntegration and Meilisearch plugins (see NorthstarMetrics statics in each).
        builder.Services.AddOpenTelemetry()
            .WithMetrics(metrics => metrics
                .AddAspNetCoreInstrumentation()
                .AddMeter("Northstar.*")
                .AddPrometheusExporter());

        var app = builder.Build();

        // Prometheus scrape endpoint on the dedicated MetricsPort only. Branched off
        // before the Nop pipeline so requests on this port never touch DB-bound
        // middleware: /metrics stays up even when this BU's database is down.
        app.MapWhen(
            context => context.Connection.LocalPort == MetricsPort,
            metricsApp =>
            {
                metricsApp.UseRouting();
                metricsApp.UseEndpoints(endpoints => endpoints.MapPrometheusScrapingEndpoint());
            });

        //configure the application HTTP request pipeline
        app.ConfigureRequestPipeline();

        await app.PublishAppStartedEventAsync();

        await app.RunAsync();
    }
}