using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Nop.Core;
using Nop.Core.Http;
using Nop.Plugin.ExternalAuth.Keycloak.Models;
using Nop.Services.Authentication.External;
using Nop.Services.Configuration;
using Nop.Services.Localization;
using Nop.Services.Messages;
using Nop.Services.Security;
using Nop.Web.Framework;
using Nop.Web.Framework.Controllers;
using Nop.Web.Framework.Mvc.Filters;

namespace Nop.Plugin.ExternalAuth.Keycloak.Controllers;

[AutoValidateAntiforgeryToken]
public class KeycloakAuthenticationController : BasePluginController
{
    protected readonly KeycloakExternalAuthSettings _settings;
    protected readonly IAuthenticationPluginManager _authenticationPluginManager;
    protected readonly IExternalAuthenticationService _externalAuthenticationService;
    protected readonly ILocalizationService _localizationService;
    protected readonly INotificationService _notificationService;
    protected readonly IOptionsMonitorCache<OpenIdConnectOptions> _optionsCache;
    protected readonly IPermissionService _permissionService;
    protected readonly ISettingService _settingService;
    protected readonly IStoreContext _storeContext;
    protected readonly IWorkContext _workContext;

    public KeycloakAuthenticationController(
        KeycloakExternalAuthSettings settings,
        IAuthenticationPluginManager authenticationPluginManager,
        IExternalAuthenticationService externalAuthenticationService,
        ILocalizationService localizationService,
        INotificationService notificationService,
        IOptionsMonitorCache<OpenIdConnectOptions> optionsCache,
        IPermissionService permissionService,
        ISettingService settingService,
        IStoreContext storeContext,
        IWorkContext workContext)
    {
        _settings = settings;
        _authenticationPluginManager = authenticationPluginManager;
        _externalAuthenticationService = externalAuthenticationService;
        _localizationService = localizationService;
        _notificationService = notificationService;
        _optionsCache = optionsCache;
        _permissionService = permissionService;
        _settingService = settingService;
        _storeContext = storeContext;
        _workContext = workContext;
    }

    [AuthorizeAdmin]
    [Area(AreaNames.ADMIN)]
    [CheckPermission(StandardPermission.Configuration.MANAGE_EXTERNAL_AUTHENTICATION_METHODS)]
    public IActionResult Configure()
    {
        var model = new ConfigurationModel
        {
            Authority = _settings.Authority,
            ClientId = _settings.ClientId,
            ClientSecret = _settings.ClientSecret
        };
        return View("~/Plugins/ExternalAuth.Keycloak/Views/Configure.cshtml", model);
    }

    [HttpPost]
    [AuthorizeAdmin]
    [Area(AreaNames.ADMIN)]
    [CheckPermission(StandardPermission.Configuration.MANAGE_EXTERNAL_AUTHENTICATION_METHODS)]
    public async Task<IActionResult> Configure(ConfigurationModel model)
    {
        if (!ModelState.IsValid)
            return Configure();

        _settings.Authority = model.Authority;
        _settings.ClientId = model.ClientId;
        _settings.ClientSecret = model.ClientSecret;
        await _settingService.SaveSettingAsync(_settings);

        // Clear cached OIDC options so the new Authority takes effect on next request
        _optionsCache.TryRemove(KeycloakAuthenticationDefaults.AuthenticationScheme);

        _notificationService.SuccessNotification(
            await _localizationService.GetResourceAsync("Admin.Plugins.Saved"));

        return Configure();
    }

    public async Task<IActionResult> Login(string returnUrl)
    {
        var store = await _storeContext.GetCurrentStoreAsync();
        var methodIsAvailable = await _authenticationPluginManager
            .IsPluginActiveAsync(KeycloakAuthenticationDefaults.SystemName,
                await _workContext.GetCurrentCustomerAsync(), store.Id);

        if (!methodIsAvailable)
            throw new NopException("Keycloak authentication module cannot be loaded");

        if (string.IsNullOrEmpty(_settings.Authority) || string.IsNullOrEmpty(_settings.ClientId))
            throw new NopException("Keycloak authentication module not configured — set Authority and ClientId in admin");

        var authenticationProperties = new AuthenticationProperties
        {
            RedirectUri = Url.Action("LoginCallback", "KeycloakAuthentication", new { returnUrl })
        };
        authenticationProperties.SetString(
            KeycloakAuthenticationDefaults.ErrorCallback,
            Url.RouteUrl(NopRouteNames.General.LOGIN, new { returnUrl }));

        return Challenge(authenticationProperties, KeycloakAuthenticationDefaults.AuthenticationScheme);
    }

    public async Task<IActionResult> LoginCallback(string returnUrl)
    {
        var authenticateResult = await HttpContext.AuthenticateAsync(
            KeycloakAuthenticationDefaults.AuthenticationScheme);

        if (!authenticateResult.Succeeded || authenticateResult.Principal?.Claims.Any() != true)
            return RedirectToRoute(NopRouteNames.General.LOGIN);

        // sub claim is the stable unique identifier from Keycloak
        var externalId = authenticateResult.Principal
            .FindFirst(ClaimTypes.NameIdentifier)?.Value
            ?? authenticateResult.Principal.FindFirst("sub")?.Value;

        var email = authenticateResult.Principal.FindFirst(ClaimTypes.Email)?.Value;

        var displayName = authenticateResult.Principal.FindFirst(ClaimTypes.Name)?.Value
            ?? authenticateResult.Principal.FindFirst("preferred_username")?.Value;

        var authenticationParameters = new ExternalAuthenticationParameters
        {
            ProviderSystemName = KeycloakAuthenticationDefaults.SystemName,
            AccessToken = await HttpContext.GetTokenAsync(
                KeycloakAuthenticationDefaults.AuthenticationScheme, "access_token"),
            Email = email,
            ExternalIdentifier = externalId,
            ExternalDisplayIdentifier = displayName,
            Claims = authenticateResult.Principal.Claims
                .Select(c => new ExternalAuthenticationClaim(c.Type, c.Value))
                .ToList()
        };

        return await _externalAuthenticationService.AuthenticateAsync(authenticationParameters, returnUrl);
    }
}
