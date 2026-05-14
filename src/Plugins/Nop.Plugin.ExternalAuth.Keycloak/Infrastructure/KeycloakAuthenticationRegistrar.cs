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

            // Resolution order: DB-stored admin settings → environment variables → safe placeholder.
            // Env-var fallback lets compose seed per-BU OIDC config without an admin click-through
            // on a fresh install. Admin UI still wins when set, so demos can override at runtime.
            var authority = FirstNonEmpty(
                settings?.Authority,
                Environment.GetEnvironmentVariable("KEYCLOAK_AUTHORITY"));
            var clientId = FirstNonEmpty(
                settings?.ClientId,
                Environment.GetEnvironmentVariable("KEYCLOAK_CLIENT_ID"));
            var clientSecret = FirstNonEmpty(
                settings?.ClientSecret,
                Environment.GetEnvironmentVariable("KEYCLOAK_CLIENT_SECRET"));

            options.Authority = string.IsNullOrEmpty(authority)
                ? "https://placeholder-not-configured"
                : authority;

            options.ClientId = string.IsNullOrEmpty(clientId)
                ? nameof(options.ClientId)
                : clientId;

            options.ClientSecret = string.IsNullOrEmpty(clientSecret)
                ? nameof(options.ClientSecret)
                : clientSecret;

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

    private static string FirstNonEmpty(params string[] candidates)
        => candidates.FirstOrDefault(c => !string.IsNullOrEmpty(c));
}
