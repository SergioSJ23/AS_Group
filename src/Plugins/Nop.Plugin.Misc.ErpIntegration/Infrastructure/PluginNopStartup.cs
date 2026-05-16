using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Nop.Core.Infrastructure;
using Nop.Plugin.Misc.ErpIntegration.Services;

namespace Nop.Plugin.Misc.ErpIntegration.Infrastructure;

public class PluginNopStartup : INopStartup
{
    public void ConfigureServices(IServiceCollection services, IConfiguration configuration)
    {
        var erpUri = configuration["ERP_URI"] ?? "http://erp:8080";

        services.AddHttpClient("erp", client =>
        {
            client.BaseAddress = new Uri(erpUri.TrimEnd('/') + "/");
            client.Timeout = TimeSpan.FromSeconds(5);
        });

        services.AddSingleton<ErpCircuitBreaker>();
        services.AddScoped<IErpStockService, ErpStockService>();
    }

    public void Configure(IApplicationBuilder application) { }

    public int Order => 3100;
}
