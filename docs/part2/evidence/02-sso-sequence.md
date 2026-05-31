# ADR-002 — SSO Flow Sequence Diagram

## Flow 1 — Login inicial na BU1

```mermaid
sequenceDiagram
    actor Alice
    participant BU1 as BU1 nopCommerce<br/>(HomeStyle :8081)
    participant KC as Keycloak<br/>(northstar realm)

    Alice->>BU1: GET /keycloakauthentication/login
    BU1-->>Alice: 302 → Keycloak<br/>client_id=bu1-nopcommerce

    Alice->>KC: GET /auth?client_id=bu1-nopcommerce
    KC-->>Alice: 200 Login form<br/>(sem KEYCLOAK_SESSION)

    Alice->>KC: POST username=alice&password=alice123
    KC-->>Alice: 302 → BU1 /signin-keycloak?code=...<br/>Set-Cookie: KEYCLOAK_SESSION ✓

    Alice->>BU1: GET /signin-keycloak?code=98d7cc8d-...
    BU1->>KC: POST /token  (troca código por tokens)
    KC-->>BU1: id_token + access_token<br/>sub=3163eb04-71e7-4509-...
    BU1-->>Alice: 302 → /<br/>Set-Cookie: .Nop.Authentication ✓

    Note over Alice,KC: ✓ Alice autenticada na BU1.<br/>Credenciais inseridas uma única vez.
```

---

## Flow 2 — SSO silencioso na BU2 (mesma sessão de browser)

```mermaid
sequenceDiagram
    actor Alice
    participant BU2 as BU2 nopCommerce<br/>(WorkSpace :8082)
    participant KC as Keycloak<br/>(northstar realm)

    Note over Alice: Browser tem KEYCLOAK_SESSION<br/>do Flow 1

    Alice->>BU2: GET /keycloakauthentication/login
    BU2-->>Alice: 302 → Keycloak<br/>client_id=bu2-nopcommerce

    Alice->>KC: GET /auth?client_id=bu2-nopcommerce<br/>Cookie: KEYCLOAK_SESSION=Mfh3zaFX...
    Note over KC: Sessão activa reconhecida<br/>para alice@example.com
    KC-->>Alice: 302 → BU2 /signin-keycloak?code=...<br/>⚡ SEM login form

    Alice->>BU2: GET /signin-keycloak?code=36b95c16-...
    BU2->>KC: POST /token  (troca código por tokens)
    KC-->>BU2: id_token + access_token<br/>sub=3163eb04-71e7-4509-... (mesmo sub)
    BU2-->>Alice: 302 → /<br/>Set-Cookie: .Nop.Authentication ✓

    Note over Alice,KC: ✓ Alice autenticada na BU2.<br/>Zero prompts de credenciais.
```

---

## Prova de isolamento de roles

```mermaid
flowchart LR
    KC[("Keycloak\nnorthstar realm\nsub: 3163eb04")]

    KC -->|"OIDC token\n(groups claim)"| BU1
    KC -->|"OIDC token\n(groups claim)"| BU2

    subgraph BU1["BU1 — HomeStyle DB"]
        C1["Customer row\nExternalId: 3163eb04\nRoles: VIP, Trade"]
    end

    subgraph BU2["BU2 — WorkSpace DB"]
        C2["Customer row\nExternalId: 3163eb04\nRoles: Wholesale, B2B"]
    end

    style KC fill:#4a9eff,color:#fff
    style BU1 fill:#e8f4e8
    style BU2 fill:#e8f4e8
```

*Mesmo `sub` (ExternalIdentifier) nos dois BUs — identidade partilhada, roles locais independentes.*
