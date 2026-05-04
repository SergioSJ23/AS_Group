using Nop.Plugin.ExternalAuth.Keycloak.Components;
using Nop.Services.Authentication.External;
using Nop.Services.Configuration;
using Nop.Services.Helpers;
using Nop.Services.Localization;
using Nop.Services.Plugins;

namespace Nop.Plugin.ExternalAuth.Keycloak;

public class KeycloakAuthenticationMethod : BasePlugin, IExternalAuthenticationMethod
{
    protected readonly ILocalizationService _localizationService;
    protected readonly ISettingService _settingService;
    protected readonly IWebHelper _webHelper;

    public KeycloakAuthenticationMethod(
        ILocalizationService localizationService,
        ISettingService settingService,
        IWebHelper webHelper)
    {
        _localizationService = localizationService;
        _settingService = settingService;
        _webHelper = webHelper;
    }

    public override string GetConfigurationPageUrl()
        => $"{_webHelper.GetStoreLocation()}Admin/KeycloakAuthentication/Configure";

    public Type GetPublicViewComponent()
        => typeof(KeycloakAuthenticationViewComponent);

    public override async Task InstallAsync()
    {
        await _settingService.SaveSettingAsync(new KeycloakExternalAuthSettings());

        await _localizationService.AddOrUpdateLocaleResourceAsync(new Dictionary<string, string>
        {
            ["Plugins.ExternalAuth.Keycloak.Authority"] = "Keycloak realm URL",
            ["Plugins.ExternalAuth.Keycloak.Authority.Hint"] = "e.g. http://keycloak.localtest.me:8080/realms/northstar",
            ["Plugins.ExternalAuth.Keycloak.ClientId"] = "Client ID",
            ["Plugins.ExternalAuth.Keycloak.ClientId.Hint"] = "The OIDC client ID registered in Keycloak for this BU",
            ["Plugins.ExternalAuth.Keycloak.ClientSecret"] = "Client Secret",
            ["Plugins.ExternalAuth.Keycloak.ClientSecret.Hint"] = "The client secret for this OIDC client",
        });

        await base.InstallAsync();
    }

    public override async Task UninstallAsync()
    {
        await _settingService.DeleteSettingAsync<KeycloakExternalAuthSettings>();
        await _localizationService.DeleteLocaleResourcesAsync("Plugins.ExternalAuth.Keycloak");
        await base.UninstallAsync();
    }
}
