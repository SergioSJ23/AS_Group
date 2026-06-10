# Spike Report — SSO with Keycloak (ADR-001)

## Objective

Prove that nopCommerce can use Keycloak as an OIDC IdP shared across multiple
Business Units, enabling SSO without re-authentication. This spike supports the decision
documented in ADR-001.

---

## What was built

### Infrastructure (`infra/spike/`)

| File | Purpose |
|---|---|
| `docker-compose.spike.yml` | Orchestration: Keycloak + 2x PostgreSQL + 2x nopCommerce |
| `keycloak/realm-northstar.json` | Realm pre-configured with two OIDC clients (`bu1-nopcommerce`, `bu2-nopcommerce`) and user `alice@example.com` |
| `pg-init/01-citext.sql` | Creates the `citext` extension in PostgreSQL - required by the nopCommerce migrations |

### Plugin (`src/Plugins/Nop.Plugin.ExternalAuth.Keycloak/`)

A nopCommerce plugin that implements `IExternalAuthenticationMethod` with OIDC via Keycloak.

Main files:

| File | Role |
|---|---|
| `KeycloakAuthenticationMethod.cs` | Plugin entry point (`BasePlugin`) |
| `Infrastructure/KeycloakAuthenticationRegistrar.cs` | Registers `AddOpenIdConnect` on the `AuthenticationBuilder` |
| `Infrastructure/RouteProvider.cs` | Routes `/keycloakauthentication/login` and `/LoginCallback` |
| `Controllers/KeycloakAuthenticationController.cs` | Configure, Login and LoginCallback actions |
| `Models/ConfigurationModel.cs` | Authority, ClientId, ClientSecret |
| `Views/Configure.cshtml` | Admin configuration form |
| `Components/KeycloakAuthenticationViewComponent.cs` | Login button on the public page |

---

## Problems encountered and resolutions

### 1. Building the OIDC plugin under the Web SDK

`Microsoft.AspNetCore.Authentication.OpenIdConnect` is an **inbox** package - it ships no
DLL of its own and relies on the ASP.NET Core shared framework. Under the standard
`Microsoft.NET.Sdk`, `AddOpenIdConnect` does not resolve at compile time (CS1061): the
`AuthenticationBuilder` type comes from Nop.Core's transitive chain (9.x) and does not match
the type the 10.x extension method expects.

**Resolution:** build the plugin with `Microsoft.NET.Sdk.Web`, which pulls in the 10.x shared
framework and makes the types consistent. That switch then requires a few project-file
adjustments:

- `OutputType=Library` - the Web SDK defaults to `Exe` (otherwise CS5001, "no Main method");
- `EnableDefaultContentItems=false` + `EnableDefaultRazorItems=false` - otherwise the SDK
  auto-includes `.cshtml`/`.json` and they collide with the explicit items (NETSDK1022);
- keep an explicit `<PackageReference ... OpenIdConnect Version="10.0.1" />` - the shared
  framework grants runtime access but not compile-time access (CS0234);
- declare the views as `<None>` with `CopyToOutputDirectory=PreserveNewest`, not `<Content>`:
  the Web SDK's Razor source generator otherwise tries to compile the plugin views at build
  time, which fails because nopCommerce compiles plugin views at runtime.

```xml
<OutputType>Library</OutputType>
<EnableDefaultContentItems>false</EnableDefaultContentItems>
<EnableDefaultRazorItems>false</EnableDefaultRazorItems>
```

### 2. Keycloak healthcheck stuck in "starting"

**Cause:** The Keycloak 26.1 image has no `curl`. The management interface is on port
9000, not 8080.

**Resolution:** Healthcheck via bash `/dev/tcp`:
```yaml
test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/localhost/9000 && printf 'GET /health/ready HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3 && grep -q UP <&3"]
```

### 3. PostgreSQL — `type "citext" does not exist`

**Cause:** nopCommerce uses the `citext` type in its migrations but the extension is not
created automatically.

**Resolution:** Initialization script `pg-init/01-citext.sql`:
```sql
CREATE EXTENSION IF NOT EXISTS citext;
```

### 4. nopCommerce — wizard loop / redirect loop

**Cause (a):** Mounting the `appsettings.json` file via a volume caused "Resource busy"
because the kernel does not allow `unlink()` on a file that is a bind-mount target.

**Cause (b):** Mounting the `App_Data` directory hid the internal localization files
(`Localization/Installation/`) that the wizard needs.

**Resolution:** Remove all `App_Data` mounts during installation. After the wizard, save the
generated `appsettings.json` and mount it as an individual file on restarts.

### 5. CS0246 — `ConfigurationModel` not found in the view

**Cause:** The plugin's `_ViewImports.cshtml` was incomplete - it was missing
`@inherits NopRazorPage<TModel>` and `@inject IWebHelper webHelper`, so a view using the
short `@model ConfigurationModel` could not resolve the type.

**Resolution:**
1. `@inherits Nop.Web.Framework.Mvc.Razor.NopRazorPage<TModel>` - gives access to the `T()` localizer
2. `@inject Nop.Services.Helpers.IWebHelper webHelper` - `IWebHelper` lives in `Nop.Services.Helpers`, not in `Nop.Core`

### 6. "Correlation failed" — SSO does not complete login in nopCommerce

**Cause:** The default `ResponseMode` of ASP.NET Core OIDC is `form_post`. Keycloak returns
the code via a cross-site POST. The browser does not send the correlation cookie
(`SameSite=Lax`) on cross-site POSTs.

**Symptom in the logs:**
```
'.AspNetCore.Correlation.xxx' cookie not found.
Error from RemoteAuthentication: Correlation failed.
```

**Resolution:** `options.ResponseMode = "query"` in `KeycloakAuthenticationRegistrar`.

---

## Result

| Acceptance Criterion | Status |
|---|---|
| AC1 — Login via Keycloak on BU1 with alice@example.com | ✅ |
| AC2 — SSO on BU2 without re-authentication | ✅ (no credential prompt) |
| AC3 — Record in `ExternalAuthenticationRecord` | To verify |

The spike confirms the feasibility of ADR-001: Keycloak works as a shared OIDC IdP for
multiple nopCommerce BUs with transparent SSO.
