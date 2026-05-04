namespace Nop.Plugin.ExternalAuth.Keycloak;

public class KeycloakAuthenticationDefaults
{
    public static string SystemName => "ExternalAuth.Keycloak";

    // ASP.NET Core authentication scheme name — must be unique across registered schemes
    public static string AuthenticationScheme => "Keycloak";

    public static string ErrorCallback => "ErrorCallback";
}
