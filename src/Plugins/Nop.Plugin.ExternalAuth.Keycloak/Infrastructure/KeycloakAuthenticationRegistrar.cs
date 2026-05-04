using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Nop.Core.Infrastructure;
using Nop.Services.Authentication.External;

namespace Nop.Plugin.ExternalAuth.Keycloak.Infrastructure;

public class KeycloakAuthenticationRegistrar : IExternalAuthenticationRegistrar
{
    public void Configure(AuthenticationBuilder builder)
    {
        builder.AddOpenIdConnect(KeycloakAuthenticationDefaults.AuthenticationScheme, options =>
        {
            var settings = EngineContext.Current.Resolve<KeycloakExternalAuthSettings>();

            // Use placeholder when not yet configured — prevents startup crash.
            // The Login action checks configuration before issuing a Challenge.
            options.Authority = string.IsNullOrEmpty(settings?.Authority)
                ? "https://placeholder-not-configured"
                : settings.Authority;

            options.ClientId = string.IsNullOrEmpty(settings?.ClientId)
                ? nameof(options.ClientId)
                : settings.ClientId;

            options.ClientSecret = string.IsNullOrEmpty(settings?.ClientSecret)
                ? nameof(options.ClientSecret)
                : settings.ClientSecret;

            // Authorization Code flow (PKCE is added automatically by the middleware)
            options.ResponseType = "code";
            options.ResponseMode = "query"; // avoid form_post so SameSite=Lax cookies are sent back
            options.SaveTokens = true;
            options.RequireHttpsMetadata = false; // HTTP is acceptable in the dev spike
            options.GetClaimsFromUserInfoEndpoint = true;

            options.Scope.Clear();
            options.Scope.Add("openid");
            options.Scope.Add("email");
            options.Scope.Add("profile");

            // ASP.NET Core OIDC middleware registers these paths automatically
            options.CallbackPath = "/signin-keycloak";
            options.SignedOutCallbackPath = "/signout-callback-keycloak";

            options.TokenValidationParameters.NameClaimType = "preferred_username";

            options.Events = new OpenIdConnectEvents
            {
                OnRemoteFailure = context =>
                {
                    context.HandleResponse();
                    var errorUrl = context.Properties?.GetString(KeycloakAuthenticationDefaults.ErrorCallback) ?? "/";
                    context.Response.Redirect(errorUrl);
                    return Task.CompletedTask;
                }
            };
        });
    }
}
