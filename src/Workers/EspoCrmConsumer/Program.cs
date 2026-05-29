using System.Text;
using EspoCrmConsumer;
using OpenTelemetry.Metrics;

var builder = WebApplication.CreateBuilder(args);

var config = builder.Configuration;
var espoCrmUrl = config["ESPOCRM_URL"] ?? "http://espocrm:80/";
var espoCrmUser = config["ESPOCRM_USER"] ?? "admin";
var espoCrmPass = config["ESPOCRM_PASS"] ?? "admin";

builder.Services.AddHttpClient("espocrm", client =>
{
    client.BaseAddress = new Uri(espoCrmUrl.TrimEnd('/') + "/");
    var credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{espoCrmUser}:{espoCrmPass}"));
    client.DefaultRequestHeaders.Add("Espo-Authorization", credentials);
});

builder.Services.AddSingleton<EspoCrmClient>();
builder.Services.AddHostedService<Worker>();

builder.Services.AddOpenTelemetry()
    .WithMetrics(metrics => metrics
        .AddMeter(CrmConsumerMetrics.MeterName)
        .AddPrometheusExporter());

var app = builder.Build();

// Prometheus scrape endpoint — picked up by observability/prometheus.yml
app.MapPrometheusScrapingEndpoint();

await app.RunAsync();
