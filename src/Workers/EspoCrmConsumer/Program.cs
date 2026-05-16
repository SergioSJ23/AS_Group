using System.Text;
using EspoCrmConsumer;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureServices((ctx, services) =>
    {
        var config = ctx.Configuration;
        var espoCrmUrl = config["ESPOCRM_URL"] ?? "http://espocrm:80/";
        var espoCrmUser = config["ESPOCRM_USER"] ?? "admin";
        var espoCrmPass = config["ESPOCRM_PASS"] ?? "admin";

        services.AddHttpClient("espocrm", client =>
        {
            client.BaseAddress = new Uri(espoCrmUrl.TrimEnd('/') + "/");
            // EspoCRM v7+ uses Espo-Authorization for API authentication (not Authorization: Basic)
            var credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{espoCrmUser}:{espoCrmPass}"));
            client.DefaultRequestHeaders.Add("Espo-Authorization", credentials);
        });

        services.AddSingleton<EspoCrmClient>();
        services.AddHostedService<Worker>();
    })
    .Build();

await host.RunAsync();
