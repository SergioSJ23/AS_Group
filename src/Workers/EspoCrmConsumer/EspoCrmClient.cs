using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace EspoCrmConsumer;

public class EspoCrmClient
{
    private readonly HttpClient _http;
    private readonly ILogger<EspoCrmClient> _logger;
    private static readonly JsonSerializerOptions _json = new(JsonSerializerDefaults.Web);

    public EspoCrmClient(IHttpClientFactory factory, ILogger<EspoCrmClient> logger)
    {
        _http = factory.CreateClient("espocrm");
        _logger = logger;
    }

    public async Task ProcessOrderAsync(OrderMessage order, CancellationToken ct)
    {
        var contactId = await FindContactByEmailAsync(order.CustomerEmail, ct);
        var notes = $"[{order.BuId}] Order #{order.OrderId} | Total: {order.OrderTotal:F2} | {order.Timestamp:u}";

        if (contactId != null)
            await UpdateContactAsync(contactId, notes, ct);
        else
            await CreateContactAsync(order, notes, ct);
    }

    private async Task<string?> FindContactByEmailAsync(string email, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(email)) return null;
        var encoded = Uri.EscapeDataString(email);
        var resp = await _http.GetAsync(
            $"api/v1/Contact?where%5B0%5D%5Btype%5D=equals&where%5B0%5D%5Bfield%5D=emailAddress&where%5B0%5D%5Bvalue%5D={encoded}", ct);

        if (!resp.IsSuccessStatusCode) return null;

        using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync(ct));
        if (doc.RootElement.TryGetProperty("list", out var list) && list.GetArrayLength() > 0)
            return list[0].GetProperty("id").GetString();

        return null;
    }

    private async Task UpdateContactAsync(string contactId, string notes, CancellationToken ct)
    {
        var body = JsonSerializer.Serialize(new { description = notes }, _json);
        using var content = new StringContent(body, Encoding.UTF8, "application/json");
        var resp = await _http.PatchAsync($"api/v1/Contact/{contactId}", content, ct);
        if (!resp.IsSuccessStatusCode)
            _logger.LogWarning("EspoCRM PATCH Contact/{Id} returned {Status}", contactId, (int)resp.StatusCode);
    }

    private async Task CreateContactAsync(OrderMessage order, string notes, CancellationToken ct)
    {
        var body = JsonSerializer.Serialize(new
        {
            firstName = "Customer",
            lastName = $"#{order.CustomerId}",
            emailAddress = order.CustomerEmail,
            description = notes
        }, _json);
        using var content = new StringContent(body, Encoding.UTF8, "application/json");
        var resp = await _http.PostAsync("api/v1/Contact", content, ct);
        if (!resp.IsSuccessStatusCode)
            _logger.LogWarning("EspoCRM POST Contact returned {Status}", (int)resp.StatusCode);
    }
}
