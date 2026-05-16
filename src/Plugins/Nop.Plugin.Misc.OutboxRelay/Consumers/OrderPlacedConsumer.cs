using Nop.Core.Domain.Orders;
using Nop.Plugin.Misc.OutboxRelay.Services;
using Nop.Services.Customers;
using Nop.Services.Events;

namespace Nop.Plugin.Misc.OutboxRelay.Consumers;

public class OrderPlacedConsumer : IConsumer<OrderPlacedEvent>
{
    private readonly IOutboxWriter _outboxWriter;
    private readonly ICustomerService _customerService;

    public OrderPlacedConsumer(IOutboxWriter outboxWriter, ICustomerService customerService)
    {
        _outboxWriter = outboxWriter;
        _customerService = customerService;
    }

    // Called by nopCommerce within the same DI scope (IDbContext instance) as the order insert,
    // so OutboxWriter.WriteAsync shares the same unit of work — dual-write hazard eliminated by construction.
    public async Task HandleEventAsync(OrderPlacedEvent eventMessage)
    {
        var order = eventMessage.Order;
        var customer = await _customerService.GetCustomerByIdAsync(order.CustomerId);

        await _outboxWriter.WriteAsync("order.placed", new
        {
            orderId = order.Id,
            orderGuid = order.OrderGuid,
            customerId = order.CustomerId,
            customerEmail = customer?.Email ?? string.Empty,
            orderTotal = order.OrderTotal,
            buId = Environment.GetEnvironmentVariable("BU_ID") ?? "unknown",
            timestamp = DateTime.UtcNow
        });
    }
}
