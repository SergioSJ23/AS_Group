# Evidence: ADR-002 — Federated Identity via Keycloak (SSO)

**QA driver:** QA3 (Federated Identity — Security / Interoperability)  
**Pressure point addressed:** P2 (customer identity is fully global)  
**Test date:** 2026-05-31

---

## Claim

A customer authenticated on BU1 navigates to BU2 without a second credential prompt.
One Keycloak session covers both BUs — different OIDC clients, same realm.

---

## Flow 1 — Initial login on BU1 (HomeStyle)

**Step 1 — BU1 initiates OIDC login**
```
GET http://localhost:8081/keycloakauthentication/login
← HTTP 302
   Location: http://keycloak.localtest.me:8080/realms/northstar/protocol/openid-connect/auth
             ?client_id=bu1-nopcommerce&...
```

**Step 2 — Keycloak serves login form (no active session yet)**
```
GET http://keycloak.localtest.me:8080/realms/northstar/...?client_id=bu1-nopcommerce&...
← HTTP 200  (login form — credentials required)
   KEYCLOAK_SESSION cookie: NOT YET SET
```

**Step 3 — alice submits credentials**
```
POST credentials  (username=alice, password=alice123)
← HTTP 302
   Set-Cookie: KEYCLOAK_SESSION=Mfh3zaFXAQtd5hhv_T4I...  (Max-Age=36000)
   Location: http://localhost:8081/signin-keycloak?code=...
```

**Step 4 — BU1 exchanges authorisation code for tokens**
```
GET http://localhost:8081/signin-keycloak?code=98d7cc8d-...
← HTTP 302
   Set-Cookie: .Nop.Authentication=...  (alice session on BU1)
   Location: /
```

**✓ Alice is authenticated on BU1. Credentials entered exactly once.**

---

## Flow 2 — Silent SSO on BU2 (WorkSpace) — same browser session

**Step 5 — BU2 initiates OIDC login**
```
GET http://localhost:8082/keycloakauthentication/login
← HTTP 302
   Location: http://keycloak.localtest.me:8080/realms/northstar/protocol/openid-connect/auth
             ?client_id=bu2-nopcommerce&...   ← different client, SAME realm
```

**Step 6 — Keycloak finds existing session — NO login form**
```
GET http://keycloak.localtest.me:8080/realms/northstar/...?client_id=bu2-nopcommerce&...
   Cookie: KEYCLOAK_SESSION=Mfh3zaFXAQtd5hhv_T4I...  (from Flow 1)

← HTTP 302  ← NO LOGIN FORM SHOWN
   Keycloak recognised active session for alice@example.com
   Issues new authorisation code for bu2-nopcommerce WITHOUT credential prompt
   Location: http://localhost:8082/signin-keycloak?code=36b95c16-...
```

**Step 7 — BU2 exchanges code for tokens**
```
GET http://localhost:8082/signin-keycloak?code=36b95c16-...
← HTTP 302
   Set-Cookie: .Nop.Authentication=...  (alice session on BU2, BU2-local roles only)
   Location: /
```

**✓ Alice is authenticated on BU2 — ZERO additional credential prompts.**

---

## Key Properties Demonstrated

| Property | Evidence |
|---|---|
| Single credential entry | Credentials entered in Step 3 only — never again |
| SSO session reuse | Step 6: Keycloak returns HTTP 302 (not 200) — no login form rendered |
| Per-BU OIDC clients | `client_id=bu1-nopcommerce` vs `client_id=bu2-nopcommerce` — same realm |
| Same identity across BUs | Both steps use `session_state=22c063c8-e2f4-44a9-8090-9dad77e6c44a` |
| BU role isolation | BU2 session gets BU2-local roles only — BU1 roles not present |

---

## Keycloak Configuration

```
Realm:   northstar
Clients: bu1-nopcommerce  →  redirect http://localhost:8081/*
         bu2-nopcommerce  →  redirect http://localhost:8082/*
Protocol: Authorization Code + PKCE  (response_mode=query)
Session:  KEYCLOAK_SESSION  Max-Age=36000s (10h sliding)
```
