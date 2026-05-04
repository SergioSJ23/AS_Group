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
            options.ResponseMode = "query";
            options.SaveTokens = true;
            options.RequireHttpsMetadata = false; // HTTP is acceptable in the dev spike

            // SameSite=None (default) requires Secure; over HTTP the browser drops the cookie
            // causing "Correlation failed". Lax works because Keycloak → BU is a top-level GET.
            options.CorrelationCookie.SameSite = Microsoft.AspNetCore.Http.SameSiteMode.Lax;
            options.CorrelationCookie.SecurePolicy = Microsoft.AspNetCore.Http.CookieSecurePolicy.SameAsRequest;
            options.NonceCookie.SameSite = Microsoft.AspNetCore.Http.SameSiteMode.Lax;
            options.NonceCookie.SecurePolicy = Microsoft.AspNetCore.Http.CookieSecurePolicy.SameAsRequest;
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
