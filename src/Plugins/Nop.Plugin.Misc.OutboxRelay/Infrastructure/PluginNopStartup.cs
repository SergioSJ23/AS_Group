using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Nop.Core.Infrastructure;
using Nop.Plugin.Misc.OutboxRelay.Services;

namespace Nop.Plugin.Misc.OutboxRelay.Infrastructure;

public class PluginNopStartup : INopStartup
{
    public void ConfigureServices(IServiceCollection services, IConfiguration configuration)
    {
        var rabbitmqUri = configuration["RABBITMQ_URI"]
            ?? Environment.GetEnvironmentVariable("RABBITMQ_URI")
            ?? "amqp://guest:guest@localhost:5672/";

        var publisher = new RabbitMqPublisher(rabbitmqUri);
        services.AddSingleton(publisher);
        services.AddScoped<IOutboxWriter, OutboxWriter>();
        services.AddHostedService<OutboxRelayService>();
    }

    public void Configure(IApplicationBuilder application) { }

    public int Order => 3100;
}
