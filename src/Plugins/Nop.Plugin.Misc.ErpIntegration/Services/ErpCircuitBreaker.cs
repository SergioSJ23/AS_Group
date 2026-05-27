using Microsoft.Extensions.Logging;

namespace Nop.Plugin.Misc.ErpIntegration.Services;

/// <summary>
/// CLOSED → (5 consecutive failures) → OPEN → (30s cooldown) → HALF-OPEN → (probe OK) → CLOSED
/// Singleton per process, so state is per-BU instance.
/// </summary>
public class ErpCircuitBreaker
{
    private enum State { Closed, Open, HalfOpen }

    private State _state = State.Closed;
    private int _failures;
    private DateTime _openedAt;
    private readonly ILogger<ErpCircuitBreaker> _logger;
    private readonly object _lock = new();

    private const int FailureThreshold = 5;
    private static readonly TimeSpan BreakDuration = TimeSpan.FromSeconds(30);

    public ErpCircuitBreaker(ILogger<ErpCircuitBreaker> logger)
    {
        _logger = logger;
    }

    public bool IsOpen
    {
        get
        {
            lock (_lock)
            {
                if (_state == State.Open && DateTime.UtcNow - _openedAt >= BreakDuration)
                {
                    _state = State.HalfOpen;
                    ErpMetrics.RecordTransition("HALFOPEN");
                    _logger.LogInformation("ERP circuit breaker → HALF-OPEN (probe allowed)");
                    return false;
                }
                return _state == State.Open;
            }
        }
    }

    public string CurrentState
    {
        get { lock (_lock) { return _state.ToString().ToUpper(); } }
    }

    public void RecordSuccess()
    {
        lock (_lock)
        {
            if (_state == State.HalfOpen)
            {
                _state = State.Closed;
                _failures = 0;
                ErpMetrics.RecordTransition("CLOSED");
                _logger.LogInformation("ERP circuit breaker → CLOSED (probe succeeded)");
            }
            else if (_state == State.Closed)
            {
                _failures = 0;
            }
        }
    }

    public void RecordFailure()
    {
        lock (_lock)
        {
            _failures++;
            if (_state == State.HalfOpen || _failures >= FailureThreshold)
            {
                var wasAlreadyOpen = _state == State.Open;
                _state = State.Open;
                _openedAt = DateTime.UtcNow;
                if (!wasAlreadyOpen)
                    ErpMetrics.RecordTransition("OPEN");
                _logger.LogWarning(
                    "ERP circuit breaker → OPEN after {Failures} failure(s). Cooldown: {Seconds}s",
                    _failures, BreakDuration.TotalSeconds);
            }
        }
    }
}
