using Nop.Core.Configuration;

namespace Nop.Plugin.ExternalAuth.Keycloak;

public class KeycloakExternalAuthSettings : ISettings
{
    // e.g. http://keycloak.localtest.me:8080/realms/northstar
    public string Authority { get; set; }

    public string ClientId { get; set; }

    public string ClientSecret { get; set; }
}
