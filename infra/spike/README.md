# Feasibility Spike — Keycloak OIDC SSO

**Spike goal (from doc 08):** Prove that a nopCommerce BU can redirect to Keycloak for login,
receive an OIDC token, and that a second BU recognises the same Keycloak session without
re-authentication.

**Addresses:** ADR-001, R1, R10.

---

## What this runs

| Service | URL (host) | Description |
|---|---|---|
| Keycloak | http://keycloak.localtest.me:8080 | Group IdP, realm `northstar` pre-loaded |
| nopCommerce BU1 | http://bu1.localtest.me:8081 | HomeStyle store, PostgreSQL `nop_bu1` |
| nopCommerce BU2 | http://bu2.localtest.me:8082 | WorkSpace store, PostgreSQL `nop_bu2` |

`localtest.me` always resolves to `127.0.0.1` — no `/etc/hosts` changes needed.

---

## Prerequisites

- Docker and Docker Compose v2
- ~6 GB RAM available for Docker
- Ports 8080, 8081, 8082 free on the host

---

## Step 1 — Start all services

From the repo root:

```bash
docker compose -f infra/spike/docker-compose.spike.yml up --build
```

The `--build` flag compiles nopCommerce including the Keycloak plugin.
First build takes ~5 minutes. Subsequent starts use the Docker cache.

Wait until you see both nopCommerce containers serving requests (look for
`Application started` in the logs).

---

## Step 2 — Complete nopCommerce installation for BU1

1. Go to **http://bu1.localtest.me:8081**
2. The setup wizard appears. Fill in:
   - **Database:** PostgreSQL
   - **Server:** `db_bu1`
   - **Port:** `5432`
   - **Database name:** `nop_bu1`
   - **Username:** `nop`
   - **Password:** `noppassword`
   - **Admin email:** `admin@bu1.com`
   - **Admin password:** anything you'll remember
   - **Store URL:** `http://bu1.localtest.me:8081/`
3. Click **Install**. Takes 1–2 minutes.

---

## Step 3 — Enable and configure Keycloak plugin in BU1

1. Log in to BU1 admin: http://bu1.localtest.me:8081/admin
2. Go to **Configuration → External Authentication Methods**
3. Enable **Keycloak authentication** → click **Edit**
4. Fill in:
   - **Authority:** `http://keycloak.localtest.me:8080/realms/northstar`
   - **Client ID:** `bu1-nopcommerce`
   - **Client Secret:** `bu1-secret`
5. Save.

---

## Step 4 — Repeat for BU2

1. Go to **http://bu2.localtest.me:8082** → complete installation wizard with:
   - Server: `db_bu2`, Database: `nop_bu2`, same user/password
   - Admin email: `admin@bu2.com`
   - Store URL: `http://bu2.localtest.me:8082/`
2. Admin → External Authentication → Enable Keycloak → Edit:
   - Authority: `http://keycloak.localtest.me:8080/realms/northstar`
   - Client ID: `bu2-nopcommerce`
   - Client Secret: `bu2-secret`

---

## Step 5 — Test SSO (acceptance criteria)

The Keycloak realm was pre-loaded with user **alice@example.com / alice123**
in the `verified-customer` group.

### AC1 — BU1 login via Keycloak

1. Open a browser (not incognito), go to **http://bu1.localtest.me:8081/login**
2. Click **Login with Keycloak (SSO)**
3. Keycloak login page appears at `keycloak.localtest.me:8080`
4. Log in as `alice@example.com` / `alice123`
5. You are redirected back to BU1 and logged in as alice

### AC2 — BU2 recognises the same session (no second login prompt)

6. In the **same browser tab**, go to **http://bu2.localtest.me:8082/login**
7. Click **Login with Keycloak (SSO)**
8. **No credentials are asked** — Keycloak sees the existing session and redirects straight back
9. You are logged in as alice on BU2

### AC3 — Customer records in each DB

Check that each BU created a `Customer` row keyed by the Keycloak `sub` claim:

```bash
# BU1 — Customer row created for alice
docker exec -it $(docker compose -f infra/spike/docker-compose.spike.yml ps -q db_bu1) \
  psql -U nop -d nop_bu1 -c \
  "SELECT \"Id\", \"Email\" FROM \"Customer\" WHERE \"Email\" = 'alice@example.com';"

# BU1 — ExternalAuthenticationRecord.ExternalIdentifier = Keycloak sub
docker exec -it $(docker compose -f infra/spike/docker-compose.spike.yml ps -q db_bu1) \
  psql -U nop -d nop_bu1 -c \
  "SELECT \"ExternalIdentifier\", \"Email\" FROM \"ExternalAuthenticationRecord\";"

# BU2 — same queries against db_bu2
```

Both DBs should show one row in `ExternalAuthenticationRecord` with the same
`ExternalIdentifier` (the Keycloak `sub` claim) and no rows shared between them.

---

## What the spike proves

| Outcome | Implication |
|---|---|
| Plugin compiles and loads | `IExternalAuthenticationMethod` seam accepts OIDC cleanly |
| OIDC redirect works | ADR-001 auth flow is viable end-to-end |
| AC2 passes (no second login) | SSO is real — Keycloak session shared across BUs |
| AC3 passes (separate DB rows) | BU isolation holds — no cross-BU customer data leakage |

If AC2 fails (BU2 still asks for password), see troubleshooting below.

---

## Troubleshooting

**`keycloak.localtest.me` not reachable from nopCommerce container**
The `extra_hosts: host-gateway` mapping in `docker-compose.spike.yml` handles this.
If it fails, verify Docker supports `host-gateway` on your platform:
```bash
docker run --rm --add-host=test:host-gateway alpine ping -c1 test
```

**BU2 still asks for login (AC2 fails)**
The browser must send the Keycloak session cookie. Ensure:
- You are using the same browser (not incognito) for both BU1 and BU2
- The Keycloak cookie domain is `keycloak.localtest.me` — since both BUs redirect to
  the same Keycloak host, the cookie is sent automatically

**nopCommerce shows 500 after wizard**
Run migrations manually:
```bash
docker compose -f infra/spike/docker-compose.spike.yml restart nop_bu1
```

---

## Clean up

```bash
docker compose -f infra/spike/docker-compose.spike.yml down -v
```

This removes containers and volumes (DB data). The built images are kept for faster restarts.
