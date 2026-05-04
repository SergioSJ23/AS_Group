# Spike Report — SSO com Keycloak (ADR-001)

## Objectivo

Provar que o nopCommerce consegue usar o Keycloak como IdP OIDC partilhado entre múltiplas
Business Units, permitindo SSO sem re-autenticação. Este spike suporta a decisão documentada
no ADR-001.

---

## O que foi construído

### Infraestrutura (`spike/`)

| Ficheiro | Propósito |
|---|---|
| `docker-compose.spike.yml` | Orquestração: Keycloak + 2× PostgreSQL + 2× nopCommerce |
| `keycloak/realm-northstar.json` | Realm pré-configurado com dois clients OIDC (`bu1-nopcommerce`, `bu2-nopcommerce`) e utilizador `alice@example.com` |
| `pg-init/01-citext.sql` | Cria a extensão `citext` no PostgreSQL — necessária para as migrações do nopCommerce |
| `app-data/bu{1,2}/appsettings.json` | Connection strings persistidas das BUs (montadas como volume para sobreviver a rebuilds) |

### Plugin (`src/Plugins/Nop.Plugin.ExternalAuth.Keycloak/`)

Plugin nopCommerce que implementa `IExternalAuthenticationMethod` com OIDC via Keycloak.

Ficheiros principais:

| Ficheiro | Papel |
|---|---|
| `KeycloakAuthenticationMethod.cs` | Ponto de entrada do plugin (`BasePlugin`) |
| `Infrastructure/KeycloakAuthenticationRegistrar.cs` | Regista `AddOpenIdConnect` no `AuthenticationBuilder` |
| `Infrastructure/RouteProvider.cs` | Rota `/keycloakauthentication/login` e `/LoginCallback` |
| `Controllers/KeycloakAuthenticationController.cs` | Acções Configure, Login e LoginCallback |
| `Models/ConfigurationModel.cs` | Authority, ClientId, ClientSecret |
| `Views/Configure.cshtml` | Formulário admin de configuração |
| `Components/KeycloakAuthenticationViewComponent.cs` | Botão de login na página pública |

---

## Decisões técnicas e porquê

### SDK: `Microsoft.NET.Sdk.Web` em vez de `Microsoft.NET.Sdk`

`Microsoft.AspNetCore.Authentication.OpenIdConnect` é um pacote **inbox** — não distribui
DLL própria, depende da shared framework do ASP.NET Core. Com `Microsoft.NET.Sdk` padrão,
o `AuthenticationBuilder.AddOpenIdConnect()` não resolve em tempo de compilação porque o
tipo `AuthenticationBuilder` vem da cadeia transitiva do Nop.Core (versão 9.x) e não
corresponde ao tipo esperado pela extension method (versão 10.x).

A solução foi usar `Microsoft.NET.Sdk.Web` que inclui automaticamente a referência à
shared framework 10.x, tornando os tipos consistentes. Foram necessárias três propriedades
adicionais:

```xml
<OutputType>Library</OutputType>           <!-- Web SDK defaulta para Exe -->
<EnableDefaultContentItems>false</EnableDefaultContentItems>
<EnableDefaultRazorItems>false</EnableDefaultRazorItems>
```

### Views como `<None>` e não `<Content>`

Com `Microsoft.NET.Sdk.Web`, os ficheiros `.cshtml` incluídos como `<Content>` são
processados pelo Razor source generator em tempo de compilação. O nopCommerce compila
views de plugins em runtime — a compilação em build time falha porque o plugin não tem
acesso ao contexto completo do nopCommerce nessa fase.

A solução foi declarar as views como `<None>` com `CopyToOutputDirectory=PreserveNewest`.
O ficheiro é copiado para o output mas o source generator ignora-o.

### `ResponseMode = "query"` no OIDC

O ASP.NET Core OIDC usa `form_post` como response mode por omissão: o Keycloak devolve
o authorization code via POST cross-site. O cookie de correlação tem `SameSite=Lax`,
pelo que o browser não o envia em POSTs cross-site → "Correlation failed".

A solução foi definir `ResponseMode = "query"`: o Keycloak redireciona via GET com o
código na query string. Em redirects GET top-level, o `SameSite=Lax` é respeitado e o
cookie é enviado.

---

## Problemas encontrados e resoluções

### 1. CS1061 — `AddOpenIdConnect` não encontrado

**Causa:** Type identity mismatch entre o `AuthenticationBuilder` transitivo do Nop.Core
(9.x) e o esperado pelo pacote OpenIdConnect 10.x.

**Resolução:** Mudar para `Microsoft.NET.Sdk.Web`.

### 2. NETSDK1022 — Duplicate Content items

**Causa:** `Microsoft.NET.Sdk.Web` inclui automaticamente `.cshtml` e `.json` como
`<Content>`. Os itens já declarados explicitamente criaram duplicados.

**Resolução:** `EnableDefaultContentItems=false` + `EnableDefaultRazorItems=false` e
declaração explícita de todos os itens.

### 3. CS0234 — Namespace OpenIdConnect não encontrado (Web SDK sem PackageReference)

**Causa:** A shared framework dá acesso em runtime mas não em compile time sem referência
explícita.

**Resolução:** Manter `<PackageReference Include="Microsoft.AspNetCore.Authentication.OpenIdConnect" Version="10.0.1" />` mesmo com o Web SDK.

### 4. Razor source generator a compilar as views em build time

**Causa:** Views como `<Content>` são processadas pelo source generator.

**Resolução:** Mudar para `<None>` com `CopyToOutputDirectory=PreserveNewest`.

### 5. CS5001 — No Main method

**Causa:** `Microsoft.NET.Sdk.Web` defaulta `OutputType=Exe`.

**Resolução:** `<OutputType>Library</OutputType>`.

### 6. Keycloak healthcheck preso em "starting"

**Causa:** A imagem Keycloak 26.1 não tem `curl`. O management interface está na porta
9000, não 8080.

**Resolução:** Healthcheck via bash `/dev/tcp`:
```yaml
test: ["CMD", "bash", "-c", "exec 3<>/dev/tcp/localhost/9000 && printf 'GET /health/ready HTTP/1.0\\r\\nHost: localhost\\r\\n\\r\\n' >&3 && grep -q UP <&3"]
```

### 7. PostgreSQL — `type "citext" does not exist`

**Causa:** O nopCommerce usa o tipo `citext` nas migrações mas a extensão não é criada
automaticamente.

**Resolução:** Script de inicialização `pg-init/01-citext.sql`:
```sql
CREATE EXTENSION IF NOT EXISTS citext;
```

### 8. nopCommerce — wizard loop / redirect loop

**Causa (a):** Mount do ficheiro `appsettings.json` via volume causava "Resource busy"
porque o kernel não permite `unlink()` num ficheiro que é bind-mount target.

**Causa (b):** Mount do directório `App_Data` escondia os ficheiros internos de
localização (`Localization/Installation/`) que o wizard precisa.

**Resolução:** Remover todos os mounts de `App_Data` durante a instalação. Após o wizard,
guardar o `appsettings.json` gerado e montá-lo como ficheiro individual em re-arranques.

### 9. CS0246 — `ConfigurationModel` não encontrado na view

**Causa real (diagnosticada):** O `_ViewImports.cshtml` do plugin **não era aplicado** à
view porque estava incompleto — faltava `@inherits NopRazorPage<TModel>` e
`@inject IWebHelper webHelper`. Como a view usa `@model ConfigurationModel` (nome curto),
a ausência do `@using` no `_ViewImports.cshtml` causava o erro.

**Diagnóstico:** Mudar a view para `@model Nop.Plugin.ExternalAuth.Keycloak.Models.ConfigurationModel`
(nome completo) confirmou que o assembly estava nas referências Razor — o erro mudou para
`webHelper` não encontrado, provando que o `_ViewImports.cshtml` não tinha os injects.

**Resolução:**
1. `@inherits Nop.Web.Framework.Mvc.Razor.NopRazorPage<TModel>` — dá acesso ao `T()` localizer
2. `@inject Nop.Services.Helpers.IWebHelper webHelper` — `IWebHelper` está em `Nop.Services.Helpers`, não em `Nop.Core`

### 10. "Correlation failed" — SSO não completa login no nopCommerce

**Causa:** `ResponseMode` padrão do ASP.NET Core OIDC é `form_post`. O Keycloak devolve
o código via POST cross-site. O browser não envia o cookie de correlação (`SameSite=Lax`)
em POSTs cross-site.

**Sintoma nos logs:**
```
'.AspNetCore.Correlation.xxx' cookie not found.
Error from RemoteAuthentication: Correlation failed.
```

**Resolução:** `options.ResponseMode = "query"` no `KeycloakAuthenticationRegistrar`.

---

## Resultado

| Critério de Aceitação | Estado |
|---|---|
| AC1 — Login via Keycloak na BU1 com alice@example.com | ✅ |
| AC2 — SSO na BU2 sem nova autenticação | ✅ (não pede credenciais) |
| AC3 — Registo em `ExternalAuthenticationRecord` | A verificar |

O spike confirma a viabilidade do ADR-001: o Keycloak funciona como IdP OIDC partilhado
para múltiplas BUs nopCommerce com SSO transparente.
