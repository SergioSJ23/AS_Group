using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using RabbitMQ.Client;
using RabbitMQ.Client.Events;

namespace EspoCrmConsumer;

public class Worker : BackgroundService
{
    private readonly EspoCrmClient _crmClient;
    private readonly ILogger<Worker> _logger;
    private readonly string _rabbitmqUri;
    // Idempotency guard: keyed by "{buId}:{orderId}" — survives duplicates within a single process lifetime.
    private readonly HashSet<string> _processed = new();

    public Worker(EspoCrmClient crmClient, ILogger<Worker> logger, IConfiguration config)
    {
        _crmClient = crmClient;
        _logger = logger;
        _rabbitmqUri = config["RABBITMQ_URI"] ?? "amqp://guest:guest@localhost:5672/";
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ConsumeAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "RabbitMQ connection lost, retrying in 5s");
                await Task.Delay(5_000, stoppingToken);
            }
        }
    }

    private async Task ConsumeAsync(CancellationToken stoppingToken)
    {
        var factory = new ConnectionFactory
        {
            Uri = new Uri(_rabbitmqUri),
            AutomaticRecoveryEnabled = true,
            ClientProvidedName = "northstar-crm-consumer"
        };

        await using var connection = await factory.CreateConnectionAsync(stoppingToken);
        await using var channel = await connection.CreateChannelAsync(cancellationToken: stoppingToken);

        await channel.ExchangeDeclareAsync("northstar.events", ExchangeType.Topic, durable: true, autoDelete: false, cancellationToken: stoppingToken);
        await channel.ExchangeDeclareAsync("northstar.dlx", ExchangeType.Fanout, durable: true, autoDelete: false, cancellationToken: stoppingToken);

        await channel.QueueDeclareAsync("northstar.crm.orders.dlq", durable: true, exclusive: false, autoDelete: false, cancellationToken: stoppingToken);
        await channel.QueueBindAsync("northstar.crm.orders.dlq", "northstar.dlx", "#", cancellationToken: stoppingToken);

        await channel.QueueDeclareAsync(
            queue: "northstar.crm.orders",
            durable: true,
            exclusive: false,
            autoDelete: false,
            arguments: new Dictionary<string, object?> { ["x-dead-letter-exchange"] = "northstar.dlx" },
            cancellationToken: stoppingToken);
        await channel.QueueBindAsync("northstar.crm.orders", "northstar.events", "*.order.placed", cancellationToken: stoppingToken);

        await channel.BasicQosAsync(prefetchSize: 0, prefetchCount: 10, global: false, cancellationToken: stoppingToken);

        var consumer = new AsyncEventingBasicConsumer(channel);
        consumer.ReceivedAsync += async (_, ea) =>
        {
            var json = Encoding.UTF8.GetString(ea.Body.ToArray());
            try
            {
                var order = JsonSerializer.Deserialize<OrderMessage>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));
                if (order == null)
                {
                    await channel.BasicAckAsync(ea.DeliveryTag, multiple: false, cancellationToken: stoppingToken);
                    return;
                }

                var key = $"{order.BuId}:{order.OrderId}";
                if (_processed.Contains(key))
                {
                    _logger.LogDebug("Skipping duplicate {Key}", key);
                    await channel.BasicAckAsync(ea.DeliveryTag, multiple: false, cancellationToken: stoppingToken);
                    return;
                }

                await _crmClient.ProcessOrderAsync(order, stoppingToken);
                _processed.Add(key);
                await channel.BasicAckAsync(ea.DeliveryTag, multiple: false, cancellationToken: stoppingToken);
                _logger.LogInformation("Processed order {Key}", key);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to process message, routing to DLQ");
                await channel.BasicNackAsync(ea.DeliveryTag, multiple: false, requeue: false, cancellationToken: stoppingToken);
            }
        };

        await channel.BasicConsumeAsync("northstar.crm.orders", autoAck: false, consumer: consumer, cancellationToken: stoppingToken);
        _logger.LogInformation("Listening on northstar.crm.orders");

        await Task.Delay(Timeout.Infinite, stoppingToken);
    }
}
