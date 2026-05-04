using Nop.Web.Framework.Models;
using Nop.Web.Framework.Mvc.ModelBinding;

namespace Nop.Plugin.ExternalAuth.Keycloak.Models;

public record ConfigurationModel : BaseNopModel
{
    [NopResourceDisplayName("Plugins.ExternalAuth.Keycloak.Authority")]
    public string Authority { get; set; }

    [NopResourceDisplayName("Plugins.ExternalAuth.Keycloak.ClientId")]
    public string ClientId { get; set; }

    [NopResourceDisplayName("Plugins.ExternalAuth.Keycloak.ClientSecret")]
    public string ClientSecret { get; set; }
}
