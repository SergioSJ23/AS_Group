using System.Text;
using RabbitMQ.Client;

namespace Nop.Plugin.Misc.OutboxRelay.Services;

public sealed class RabbitMqPublisher : IAsyncDisposable
{
    private readonly ConnectionFactory _factory;
    private IConnection? _connection;
    private IChannel? _channel;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public RabbitMqPublisher(string uri)
    {
        _factory = new ConnectionFactory
        {
            Uri = new Uri(uri),
            AutomaticRecoveryEnabled = true,
            ClientProvidedName = "northstar-outbox-relay"
        };
    }

    private async Task EnsureChannelAsync()
    {
        if (_channel is { IsOpen: true }) return;
        await _lock.WaitAsync();
        try
        {
            if (_channel is { IsOpen: true }) return;
            if (_connection == null || !_connection.IsOpen)
                _connection = await _factory.CreateConnectionAsync();
            _channel = await _connection.CreateChannelAsync();
            await _channel.ExchangeDeclareAsync("northstar.events", ExchangeType.Topic, durable: true, autoDelete: false);
            await _channel.ExchangeDeclareAsync("northstar.dlx", ExchangeType.Fanout, durable: true, autoDelete: false);
            await _channel.QueueDeclareAsync(
                queue: "northstar.crm.orders.dlq",
                durable: true,
                exclusive: false,
                autoDelete: false);
            await _channel.QueueBindAsync("northstar.crm.orders.dlq", "northstar.dlx", "#");
            await _channel.QueueDeclareAsync(
                queue: "northstar.crm.orders",
                durable: true,
                exclusive: false,
                autoDelete: false,
                arguments: new Dictionary<string, object?> { ["x-dead-letter-exchange"] = "northstar.dlx" });
            await _channel.QueueBindAsync("northstar.crm.orders", "northstar.events", "*.order.placed");
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task PublishAsync(string routingKey, string payload, CancellationToken cancellationToken = default)
    {
        await EnsureChannelAsync();
        var body = Encoding.UTF8.GetBytes(payload);
        var props = new BasicProperties { Persistent = true };
        await _channel!.BasicPublishAsync("northstar.events", routingKey, false, props, body, cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        if (_channel != null) await _channel.DisposeAsync();
        if (_connection != null) await _connection.DisposeAsync();
        _lock.Dispose();
    }
}
