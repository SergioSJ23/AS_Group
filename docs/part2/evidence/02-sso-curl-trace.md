# ADR-002 — SSO Curl Trace

**Date:** 2026-05-31T17:25:53Z  
**User:** alice / alice123

---

## Flow 1 — Login na BU1

```
GET http://localhost:8081/keycloakauthentication/login
← 302  Location: http://keycloak.localtest.me:8080/realms/northstar/...
         ?client_id=bu1-nopcommerce
```

```
GET http://keycloak.localtest.me:8080/realms/northstar/...?client_id=bu1-nopcommerce
← 200  (Keycloak login form — pede credenciais)
         KEYCLOAK_SESSION: NOT SET
```

```
POST username=alice&password=alice123
← 302  Set-Cookie: KEYCLOAK_SESSION=Mfh3zaFXAQtd5hhv_T4I...
         Location: http://localhost:8081/signin-keycloak?code=98d7cc8d-...
```

```
GET http://localhost:8081/signin-keycloak?code=98d7cc8d-...
← 302  Set-Cookie: .Nop.Authentication=...
         Location: /
```

**✓ Alice autenticada na BU1. Credenciais inseridas uma única vez.**

---

## Flow 2 — Navega para BU2 (mesma sessão)

```
GET http://localhost:8082/keycloakauthentication/login
← 302  Location: http://keycloak.localtest.me:8080/realms/northstar/...
         ?client_id=bu2-nopcommerce     ← cliente diferente, mesmo realm
```

```
GET http://keycloak.localtest.me:8080/realms/northstar/...?client_id=bu2-nopcommerce
     Cookie: KEYCLOAK_SESSION=Mfh3zaFXAQtd5hhv_T4I...

← 302  (sem login form — sessão reconhecida)
         Location: http://localhost:8082/signin-keycloak?code=36b95c16-...
```

```
GET http://localhost:8082/signin-keycloak?code=36b95c16-...
← 302  Set-Cookie: .Nop.Authentication=...
         Location: /
```

**✓ Alice autenticada na BU2 — zero prompts de credenciais.**
