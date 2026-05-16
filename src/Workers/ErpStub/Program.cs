var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var buId = Environment.GetEnvironmentVariable("ERP_BU_ID") ?? "unknown";
var broken = false;

app.MapGet("/health", () => Results.Ok(new { status = broken ? "degraded" : "ok", buId }));

app.MapGet("/stock/{sku}", (string sku) =>
{
    if (broken)
        return Results.StatusCode(503);

    var quantity = Math.Abs(sku.GetHashCode()) % 100 + 1;
    return Results.Ok(new { sku, quantity, warehouseId = $"WH-{buId.ToUpper()}" });
});

app.MapPost("/admin/break", () =>
{
    broken = true;
    return Results.Ok(new { status = "broken", buId });
});

app.MapPost("/admin/recover", () =>
{
    broken = false;
    return Results.Ok(new { status = "recovered", buId });
});

await app.RunAsync();
