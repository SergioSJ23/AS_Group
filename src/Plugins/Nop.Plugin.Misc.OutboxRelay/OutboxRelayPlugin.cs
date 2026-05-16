using Nop.Services.Common;
using Nop.Services.Plugins;

namespace Nop.Plugin.Misc.OutboxRelay;

public class OutboxRelayPlugin : BasePlugin, IMiscPlugin
{
    public override string GetConfigurationPageUrl() => string.Empty;
}
