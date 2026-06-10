# How to Test the Spike — SSO with Keycloak (ADR-001)

## Prerequisites

- Docker and Docker Compose installed
- Ports 8080, 8081, 8082 free on the host
- `localtest.me` needs no configuration — it always resolves to 127.0.0.1

---

## Per-session flow

The spike is designed to be completely clean on every session: each `up --build` starts
from scratch, the wizard always runs, and `down -v` destroys everything. There is no
persistent state between sessions.

```
docker compose up --build   →  wizard  →  configure plugin  →  test SSO
docker compose down -v      →  everything wiped, ready for the next session
```

---

## 1. Startup

From the repository root:

```bash
docker compose -f infra/spike/docker-compose.spike.yml up --build
```

The `--build` compiles nopCommerce including the Keycloak plugin (first time ~5 min,
later runs use the Docker cache).

Wait until the logs show the nopCommerce containers serving requests
(`Application started`).

---

## 2. nopCommerce installation wizard

The wizard always runs because there is no persisted `appsettings.json`. Open it in two tabs:

### BU1 — HomeStyle

1. Go to `http://bu1.localtest.me:8081`
2. Fill in:
   - **Admin e-mail:** `admin@bu1.com`
   - **Admin password:** `Admin123!`
   - **Database:** PostgreSQL
   - **Server:** `db_bu1`
   - **Database name:** `nop_bu1`
   - **Username:** `nop`
   - **Password:** `noppassword`
3. Submit — wait for the automatic restart (~2 min)
4. When the container stops, run:
   ```bash
   docker compose -f infra/spike/docker-compose.spike.yml start nop_bu1
   ```

### BU2 — WorkSpace

1. Go to `http://bu2.localtest.me:8082`
2. Same options, except:
   - **Server:** `db_bu2`
   - **Database name:** `nop_bu2`
   - **Admin e-mail:** `admin@bu2.com`
3. Submit — wait for the automatic restart
4. When the container stops, run:
   ```bash
   docker compose -f infra/spike/docker-compose.spike.yml start nop_bu2
   ```

---

## 3. Configure the Keycloak plugin in each BU

### BU1

1. `http://bu1.localtest.me:8081/login` → log in with `admin@bu1.com` / `Admin123!`
2. **Admin → Configuration → External Authentication Methods**
3. Edit **Keycloak** → enable → **Configure**:
   - **Authority:** `http://keycloak.localtest.me:8080/realms/northstar`
   - **Client ID:** `bu1-nopcommerce`
   - **Client Secret:** `bu1-secret`
4. Save

### BU2

1. `http://bu2.localtest.me:8082/login` → log in with `admin@bu2.com` / `Admin123!`
2. Same process, with:
   - **Client ID:** `bu2-nopcommerce`
   - **Client Secret:** `bu2-secret`
3. Save

---

## 4. SSO test — acceptance criteria

### AC1 — Login via Keycloak on BU1

1. Open `http://bu1.localtest.me:8081/login` in **private/incognito** mode
2. Click the **Keycloak** button
3. Log in as `alice@example.com` / `alice123`
4. **Expected result:** redirected back to BU1, authenticated as alice

### AC2 — SSO on BU2 without re-authentication

1. In the **same window** (do not open a new incognito window), go to `http://bu2.localtest.me:8082/login`
2. Click **Keycloak**
3. **Expected result:** no credential prompt — automatically authenticated as alice

> This is the critical ADR-001 test: a single Keycloak session shared across two BUs.

### AC3 — Database record

```bash
# BU1
docker exec spike-db_bu1-1 psql -U nop -d nop_bu1 -c \
  "SELECT ExternalIdentifier, Email FROM \"ExternalAuthenticationRecord\";"

# BU2
docker exec spike-db_bu2-1 psql -U nop -d nop_bu2 -c \
  "SELECT ExternalIdentifier, Email FROM \"ExternalAuthenticationRecord\";"
```

**Expected result:** one row in each DB with the Keycloak `sub` claim (UUID) and `alice@example.com`.

---

## 5. Stop and clean up

```bash
docker compose -f infra/spike/docker-compose.spike.yml down -v
```

Removes containers, network, and DB volumes. The next session starts again from step 1.

---

## Reference credentials

| Service | URL | User | Password |
|---|---|---|---|
| Keycloak Admin | `http://keycloak.localtest.me:8080` | `admin` | `admin` |
| Test user | — | `alice@example.com` | `alice123` |
| nopCommerce BU1 | `http://bu1.localtest.me:8081` | `admin@bu1.com` | `Admin123!` |
| nopCommerce BU2 | `http://bu2.localtest.me:8082` | `admin@bu2.com` | `Admin123!` |

---

## Troubleshooting

**`keycloak.localtest.me` not reachable from the nopCommerce container**
The `extra_hosts: host-gateway` in `docker-compose.spike.yml` handles this. If it fails:
```bash
docker run --rm --add-host=test:host-gateway alpine ping -c1 test
```

**BU2 still asks for login (AC2 fails)**
The browser must send the Keycloak session cookie. Make sure you are using the
same browser window (not a new incognito window) for both BUs.

**nopCommerce shows 500 after the wizard**
```bash
docker compose -f infra/spike/docker-compose.spike.yml restart nop_bu1
```
