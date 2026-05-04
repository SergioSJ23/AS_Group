using Microsoft.AspNetCore.Mvc;
using Nop.Web.Framework.Components;

namespace Nop.Plugin.ExternalAuth.Keycloak.Components;

public class KeycloakAuthenticationViewComponent : NopViewComponent
{
    public async Task<IViewComponentResult> InvokeAsync(string widgetZone, object additionalData)
    {
        return await ViewAsync("~/Plugins/ExternalAuth.Keycloak/Views/PublicInfo.cshtml");
    }
}
