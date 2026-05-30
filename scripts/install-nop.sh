#!/usr/bin/env bash
# Automates the nopCommerce web installer for BU1 (port 8081) and BU2 (port 8082).
#
# Each call:
#   1. GET /install — picks up the antiforgery cookie + hidden form token.
#   2. POST /Install/Index with PostgreSQL config pointing at the matching db_buN service,
#      using a raw connection string so the installer skips the per-field builder.
#
# Skips a BU if it already redirects from /install (i.e. is already installed).
# Idempotent: safe to re-run.
#
# Run from the repo root after `docker compose up -d` and after both nop_buN containers
# are serving the install page.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Must satisfy nopCommerce's default policy: ≥6 chars, upper, lower, digit, symbol.
# Override: ADMIN_PASSWORD=YourPass ./scripts/install-nop.sh
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"

echo "==> Pre-flight checks"
for c in northstar-db_bu1-1 northstar-db_bu2-1 northstar-nop_bu1-1 northstar-nop_bu2-1; do
    if ! docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null | grep -q true; then
        echo "FAIL: container '${c}' is not running. Run 'docker compose up -d' first, wait ~30s, then re-run this script."
        exit 1
    fi
done
echo "    all required containers running"

# nopCommerce installer checks write permissions on wwwroot/images/uploaded.
# The directory is bind-mounted from ./assets/images/bu{1,2} which may be owned
# by the host user (non-root). Ensure the directory is world-writable so the
# installer's ACL check passes regardless of ownership.
echo "==> Fixing bind-mount permissions for installer ACL check"
chmod -f 777 \
    "${SCRIPT_DIR}/../assets/images/bu1" \
    "${SCRIPT_DIR}/../assets/images/bu2" 2>/dev/null || true
echo "    done"

# Waits until a nopCommerce port responds with any HTTP status code (including 302
# to /install). "Connection reset by peer" happens while Kestrel is still initialising;
# we retry every 3 s for up to 3 minutes.
wait_for_http () {
    local port="$1" label="$2"
    echo "==> Waiting for :${port} (${label}) to accept HTTP…"
    for _ in $(seq 1 60); do
        local code
        code=$(curl -sS -o /dev/null -w '%{http_code}' \
            --connect-timeout 3 --max-time 5 \
            "http://localhost:${port}/" 2>/dev/null || true)
        if [ -n "$code" ] && [ "$code" != "000" ]; then
            echo "    :${port} ready (HTTP ${code})"
            return 0
        fi
        sleep 3
    done
    echo "FAIL: :${port} did not respond after 3 min — is the container healthy?"
    exit 1
}

wait_for_http 8081 nop_bu1
wait_for_http 8082 nop_bu2

# Detect admin email per-BU from the database (first non-system account).
# On a fresh install (no DB tables yet) this returns empty; the caller falls back to a default.
# Always returns 0 so set -e + pipefail don't kill the script before fallback runs.
detect_admin_email () {
    local db_container="$1" db_name="$2"
    local out
    out=$(docker exec "$db_container" psql -U nop -d "$db_name" -tAc \
        "SELECT \"Email\" FROM \"Customer\" WHERE \"IsSystemAccount\" = false AND \"Email\" IS NOT NULL ORDER BY \"Id\" LIMIT 1;" 2>/dev/null || true)
    printf '%s' "$out" | tr -d '[:space:]'
    return 0
}

ADMIN_EMAIL_BU1="${ADMIN_EMAIL_BU1:-$(detect_admin_email "northstar-db_bu1-1" "nop_bu1")}"
ADMIN_EMAIL_BU1="${ADMIN_EMAIL_BU1:-admin@bu1.northstar.local}"
ADMIN_EMAIL_BU2="${ADMIN_EMAIL_BU2:-$(detect_admin_email "northstar-db_bu2-1" "nop_bu2")}"
ADMIN_EMAIL_BU2="${ADMIN_EMAIL_BU2:-admin@bu2.northstar.local}"

bu_email () {
    if [ "$1" = "bu1" ]; then echo "$ADMIN_EMAIL_BU1"; else echo "$ADMIN_EMAIL_BU2"; fi
}
echo "Detected admin emails: BU1=${ADMIN_EMAIL_BU1}  BU2=${ADMIN_EMAIL_BU2}"

install_bu () {
    local bu="$1" host_port="$2" db_host="$3" db_name="$4"
    local base="http://localhost:${host_port}"
    local conn="Server=${db_host};Port=5432;Database=${db_name};User Id=nop;Password=noppassword;"

    echo "==> ${bu}: probing ${base}/"

    # If / returns 200 already, the storefront is up and installed — nothing to do.
    if [ "$(curl -sS -o /dev/null -w '%{http_code}' "${base}/")" = "200" ]; then
        echo "    already installed (storefront serving) — skipping"
        return 0
    fi

    local cookies
    cookies=$(mktemp)
    trap 'rm -f "$cookies"' RETURN

    local install_html http
    http=$(curl -sS -o "$cookies.html" -w '%{http_code}' \
        -c "$cookies" -b "$cookies" \
        "${base}/install")
    install_html=$(cat "$cookies.html")
    rm -f "$cookies.html"

    if ! printf '%s' "$install_html" | grep -q 'name="__RequestVerificationToken"'; then
        echo "FAIL: ${base}/install did not return the install form (HTTP ${http})"
        return 1
    fi

    local token
    token=$(printf '%s' "$install_html" \
        | grep -oE 'name="__RequestVerificationToken"[^>]*value="[^"]+"' \
        | head -1 \
        | sed -E 's/.*value="([^"]+)".*/\1/')
    if [ -z "$token" ]; then
        echo "FAIL: could not extract antiforgery token from ${base}/install"
        return 1
    fi

    echo "    posting installer form…"
    local resp_body
    resp_body=$(mktemp)
    local post_status
    post_status=$(curl -sS -o "$resp_body" -w '%{http_code}' \
        -c "$cookies" -b "$cookies" \
        -X POST "${base}/Install/Index" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "AdminEmail=$(bu_email "$bu")" \
        --data-urlencode "AdminPassword=${ADMIN_PASSWORD}" \
        --data-urlencode "ConfirmPassword=${ADMIN_PASSWORD}" \
        --data-urlencode "DataProvider=PostgreSQL" \
        --data-urlencode "ConnectionStringRaw=true" \
        --data-urlencode "ConnectionString=${conn}" \
        --data-urlencode "CreateDatabaseIfNotExists=false" \
        --data-urlencode "IntegratedSecurity=false" \
        --data-urlencode "UseCustomCollation=false" \
        --data-urlencode "InstallSampleData=false" \
        --data-urlencode "InstallRegionalResources=true" \
        --data-urlencode "SubscribeNewsletters=false" \
        --data-urlencode "Country=US")

    # The installer responds with HTTP 200 on both success and validation failure.
    # Distinguish by looking for a "Setup failed:" message in the response body.
    local setup_error
    setup_error=$(grep -oE 'Setup failed: [^<]+' "$resp_body" | head -1 || true)
    rm -f "$resp_body"

    if [ -n "$setup_error" ]; then
        echo "FAIL: installer reported: ${setup_error}"
        echo "      Common cause: half-installed DB. Try resetting with:"
        echo "      docker exec northstar-${db_host}-1 psql -U nop -d ${db_name} -c \\"
        echo "        \"DROP SCHEMA public CASCADE; CREATE SCHEMA public; CREATE EXTENSION IF NOT EXISTS citext;\""
        echo "      then docker compose restart nop_${bu} and re-run this script."
        return 1
    fi

    case "$post_status" in
        200|302)
            echo "    HTTP ${post_status} — installer accepted; storefront needs a process restart"
            ;;
        *)
            echo "FAIL: installer POST returned HTTP ${post_status}"
            return 1
            ;;
    esac
}

install_bu bu1 8081 db_bu1 nop_bu1
install_bu bu2 8082 db_bu2 nop_bu2

# nopCommerce writes dataSettings.json asynchronously after the installer POST,
# then calls StopApplication(). Wait for the file to appear before restarting so
# we don't kill the process while migrations are still running.
wait_for_datasettings () {
    local container="$1" bu="$2"
    echo "==> Waiting for ${bu} connection string to be written to appsettings.json…"
    for _ in $(seq 1 120); do
        # nopCommerce 4.7+ writes the connection string into App_Data/appsettings.json
        local cs
        cs=$(docker exec "$container" \
            sh -c 'cat /app/App_Data/appsettings.json 2>/dev/null | grep -o "\"ConnectionString\":[[:space:]]*\"[^\"]\+\"" | head -1' 2>/dev/null || true)
        if [ -n "$cs" ] && [ "$cs" != *'""'* ]; then
            echo "    connection string written for ${bu}"
            return 0
        fi
        sleep 2
    done
    echo "FAIL: connection string never appeared in appsettings.json for ${bu}"
    exit 1
}

wait_for_datasettings northstar-nop_bu1-1 bu1
wait_for_datasettings northstar-nop_bu2-1 bu2

echo
echo "==> Restarting nop containers so appsettings.json is reloaded"
docker compose restart nop_bu1 nop_bu2 >/dev/null

wait_for_storefront () {
    local port="$1"
    for _ in $(seq 1 90); do
        if [ "$(curl -sS -o /dev/null -w '%{http_code}' "http://localhost:${port}/" 2>/dev/null || echo 000)" = "200" ]; then
            return 0
        fi
        sleep 1
    done
    return 1
}

echo "==> Waiting for storefronts to serve / with HTTP 200"
for port in 8081 8082; do
    if wait_for_storefront "$port"; then
        echo "    :${port} is live"
    else
        echo "FAIL: :${port} did not return HTTP 200 after restart"
        exit 1
    fi
done

# ── Per-BU configuration ──────────────────────────────────────────────────
# Sets the store name for a BU via a direct DB write.
configure_bu () {
    local bu="$1" store_name="$2"
    local db_container="northstar-db_${bu}-1"
    local db_name="nop_${bu}"

    echo "==> ${bu}: configuring store name '${store_name}'"
    docker exec "$db_container" psql -U nop -d "$db_name" -c \
        "UPDATE \"Store\" SET \"Name\" = '${store_name}' WHERE \"Id\" = 1;" >/dev/null
    echo "    done"
}

# Seeds per-BU products by piping the matching SQL file into psql.
# Must be called BEFORE install_meilisearch_plugin so BulkIndexAsync finds the rows.
seed_bu_products () {
    local bu="$1"
    local db_container="northstar-db_${bu}-1"
    local db_name="nop_${bu}"
    local sql_file="${SCRIPT_DIR}/seed-${bu}.sql"

    echo "==> ${bu}: seeding products from ${sql_file}"
    docker exec -i "$db_container" psql -U nop -d "$db_name" < "$sql_file"
    echo "    done"
}

# Helpers for the admin flow: log in as the admin, drive plugin install + activation.
# The plugin list page reuses POST /Admin/Plugin/List with form fields that match the
# [FormValueRequired(StartsWith, "install-plugin-link-")] dispatcher.

extract_token () {
    grep -oE 'name="__RequestVerificationToken"[^>]*value="[^"]+"' "$1" \
        | head -1 \
        | sed -E 's/.*value="([^"]+)".*/\1/'
}

admin_login () {
    local bu="$1" host_port="$2" cookies="$3" email="$4"
    local base="http://localhost:${host_port}"
    local html
    html=$(mktemp)

    curl -sS -c "$cookies" -b "$cookies" -o "$html" "${base}/login" || {
        echo "FAIL: ${bu} GET /login failed"; rm -f "$html"; return 1;
    }
    local token
    token=$(extract_token "$html")
    rm -f "$html"
    [ -n "$token" ] || { echo "FAIL: no token on ${bu} /login"; return 1; }

    local code
    code=$(curl -sS -o /dev/null -w '%{http_code}' \
        -c "$cookies" -b "$cookies" \
        -X POST "${base}/login" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "Email=${email}" \
        --data-urlencode "Password=${ADMIN_PASSWORD}" \
        --data-urlencode "RememberMe=false")
    case "$code" in
        302) ;;
        *)
            echo "FAIL: ${bu} login POST returned HTTP ${code} (email=${email})"
            echo "      The admin password does not match ADMIN_PASSWORD='${ADMIN_PASSWORD}'."
            echo "      Fix: ADMIN_PASSWORD=<your-password> ./scripts/install-nop.sh"
            echo "      Or seed Meilisearch directly: ./scripts/seed-meilisearch.sh"
            return 1
            ;;
    esac
}

plugin_already_installed () {
    local cookies="$1" base="$2"
    # If the plugin row exposes an "uninstall-plugin-link-ExternalAuth.Keycloak"
    # button, then it's already installed and active on the running process.
    curl -sS -b "$cookies" -c "$cookies" "${base}/Admin/Plugin/List" \
        | grep -q 'uninstall-plugin-link-ExternalAuth.Keycloak'
}

install_keycloak_plugin () {
    local bu="$1" host_port="$2"
    local base="http://localhost:${host_port}"
    local cookies
    cookies=$(mktemp)
    trap 'rm -f "$cookies"' RETURN

    echo "==> ${bu}: enabling ExternalAuth.Keycloak plugin"
    admin_login "$bu" "$host_port" "$cookies" "$(bu_email "$bu")" || return 1

    if plugin_already_installed "$cookies" "$base"; then
        echo "    plugin already installed — skipping install step"
        return 0
    fi

    local html token code
    html=$(mktemp)
    curl -sS -b "$cookies" -c "$cookies" -o "$html" "${base}/Admin/Plugin/List"
    token=$(extract_token "$html")
    rm -f "$html"
    [ -n "$token" ] || { echo "FAIL: no token on ${bu} Plugin/List"; return 1; }

    echo "    prepare install"
    code=$(curl -sS -o /dev/null -w '%{http_code}' \
        -b "$cookies" -c "$cookies" \
        -X POST "${base}/Admin/Plugin/List" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "install-plugin-link-ExternalAuth.Keycloak=1")
    case "$code" in
        200|302) ;;
        *) echo "FAIL: ${bu} install POST returned HTTP ${code}"; return 1 ;;
    esac

    echo "    apply changes (this triggers an in-process restart)"
    curl -sS -o /dev/null -b "$cookies" -c "$cookies" \
        -X POST "${base}/Admin/Plugin/List" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "plugin-apply-changes=1" || true
}

activate_keycloak_method () {
    local bu="$1" host_port="$2"
    local base="http://localhost:${host_port}"
    local cookies
    cookies=$(mktemp)
    trap 'rm -f "$cookies"' RETURN

    echo "==> ${bu}: marking Keycloak as active external auth method"
    admin_login "$bu" "$host_port" "$cookies" "$(bu_email "$bu")" || return 1

    local html token code
    html=$(mktemp)
    curl -sS -b "$cookies" -c "$cookies" -o "$html" \
        "${base}/Admin/Authentication/ExternalMethods"
    token=$(extract_token "$html")
    rm -f "$html"
    [ -n "$token" ] || { echo "FAIL: no token on ${bu} ExternalMethods"; return 1; }

    code=$(curl -sS -o /dev/null -w '%{http_code}' \
        -b "$cookies" -c "$cookies" \
        -X POST "${base}/Admin/Authentication/ExternalMethodUpdate" \
        -H "X-Requested-With: XMLHttpRequest" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "SystemName=ExternalAuth.Keycloak" \
        --data-urlencode "IsActive=true" \
        --data-urlencode "DisplayOrder=1")
    case "$code" in
        200|204|302) echo "    active (HTTP ${code})" ;;
        *) echo "FAIL: ${bu} activation returned HTTP ${code}"; return 1 ;;
    esac
}

install_outbox_plugin () {
    local bu="$1"
    local db_container="northstar-db_${bu}-1"
    local db_name="nop_${bu}"

    echo "==> ${bu}: installing Misc.OutboxRelay plugin"

    # 1. Create the OutboxMessage table if it doesn't exist (nopCommerce migration
    #    MigrationProcessType.Installation only runs via the admin UI install button,
    #    so we ensure the schema is present before the plugin loads).
    docker exec "$db_container" psql -U nop -d "$db_name" -c "
        CREATE TABLE IF NOT EXISTS \"OutboxMessage\" (
            \"Id\"          serial PRIMARY KEY,
            \"BuId\"        varchar(50)  NOT NULL DEFAULT '',
            \"EventType\"   varchar(200) NOT NULL DEFAULT '',
            \"Payload\"     text         NOT NULL DEFAULT '',
            \"CreatedAt\"   timestamp    NOT NULL DEFAULT now(),
            \"PublishedAt\" timestamp    NULL
        );" >/dev/null
    echo "    OutboxMessage table ready"

    # 2. Inject into plugins.json so nopCommerce loads and starts the relay service.
    local plugins_file; plugins_file=$(mktemp)
    docker cp "${db_container/db_/nop_}-1:/app/App_Data/plugins.json" "$plugins_file" 2>/dev/null || \
    docker cp "northstar-nop_${bu}-1:/app/App_Data/plugins.json" "$plugins_file"
    python3 - "$plugins_file" <<'PYEOF'
import sys, json
path = sys.argv[1]
with open(path, 'rb') as f:
    data = json.loads(f.read().decode('utf-8-sig'))
names = [p['SystemName'] for p in data['InstalledPlugins']]
if 'Misc.OutboxRelay' not in names:
    data['InstalledPlugins'].append({'SystemName': 'Misc.OutboxRelay', 'Version': '1.00.0'})
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
PYEOF
    docker cp "$plugins_file" "northstar-nop_${bu}-1:/app/App_Data/plugins.json"
    rm -f "$plugins_file"
    echo "    plugins.json updated"
}

install_erp_plugin () {
    local bu="$1" host_port="$2"
    local base="http://localhost:${host_port}"
    local cookies
    cookies=$(mktemp)
    trap 'rm -f "$cookies"' RETURN

    echo "==> ${bu}: enabling Misc.ErpIntegration plugin"
    admin_login "$bu" "$host_port" "$cookies" "$(bu_email "$bu")" || return 1

    # Already installed if the uninstall button is present.
    if curl -sS -b "$cookies" -c "$cookies" "${base}/Admin/Plugin/List" \
            | grep -q 'uninstall-plugin-link-Misc.ErpIntegration'; then
        echo "    plugin already installed — skipping install step"
        return 0
    fi

    local html token code
    html=$(mktemp)
    curl -sS -b "$cookies" -c "$cookies" -o "$html" "${base}/Admin/Plugin/List"
    token=$(extract_token "$html")
    rm -f "$html"
    [ -n "$token" ] || { echo "FAIL: no token on ${bu} Plugin/List"; return 1; }

    echo "    prepare install"
    code=$(curl -sS -o /dev/null -w '%{http_code}' \
        -b "$cookies" -c "$cookies" \
        -X POST "${base}/Admin/Plugin/List" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "install-plugin-link-Misc.ErpIntegration=1")
    case "$code" in
        200|302) ;;
        *) echo "FAIL: ${bu} install POST returned HTTP ${code}"; return 1 ;;
    esac

    echo "    apply changes (triggers in-process restart)"
    curl -sS -o /dev/null -b "$cookies" -c "$cookies" \
        -X POST "${base}/Admin/Plugin/List" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "plugin-apply-changes=1" || true
}

activate_erp_widget () {
    local bu="$1" host_port="$2"
    local base="http://localhost:${host_port}"
    local cookies
    cookies=$(mktemp)
    trap 'rm -f "$cookies"' RETURN

    echo "==> ${bu}: activating Misc.ErpIntegration widget"
    admin_login "$bu" "$host_port" "$cookies" "$(bu_email "$bu")" || return 1

    local html token code
    html=$(mktemp)
    curl -sS -b "$cookies" -c "$cookies" -o "$html" "${base}/Admin/Widget/List"
    token=$(extract_token "$html")
    rm -f "$html"
    [ -n "$token" ] || { echo "FAIL: no token on ${bu} Widget/List"; return 1; }

    code=$(curl -sS -o /dev/null -w '%{http_code}' \
        -b "$cookies" -c "$cookies" \
        -X POST "${base}/Admin/Widget/WidgetUpdate" \
        -H "X-Requested-With: XMLHttpRequest" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "SystemName=Misc.ErpIntegration" \
        --data-urlencode "IsActive=true" \
        --data-urlencode "DisplayOrder=1")
    case "$code" in
        200|204|302) echo "    widget active (HTTP ${code})" ;;
        *) echo "FAIL: ${bu} widget activation returned HTTP ${code}"; return 1 ;;
    esac
}

# Search.Meilisearch self-activates as both ISearchProvider and IWidgetPlugin inside its
# own InstallAsync (CatalogSettings.ActiveSearchProviderSystemName + WidgetSettings), so
# the shell side only has to drive plugin install + apply-changes.
install_meilisearch_plugin () {
    local bu="$1" host_port="$2"
    local base="http://localhost:${host_port}"
    local cookies
    cookies=$(mktemp)
    trap 'rm -f "$cookies"' RETURN

    echo "==> ${bu}: enabling Search.Meilisearch plugin"
    admin_login "$bu" "$host_port" "$cookies" "$(bu_email "$bu")" || return 1

    # If already installed, uninstall first so InstallAsync (+ BulkIndexAsync) runs again.
    # This ensures pictureUrl and other new fields are always re-indexed after a rebuild.
    local plugin_page
    plugin_page=$(curl -sS -b "$cookies" -c "$cookies" "${base}/Admin/Plugin/List")
    if printf '%s' "$plugin_page" | grep -q 'uninstall-plugin-link-Search.Meilisearch'; then
        echo "    already installed — uninstalling first to force re-index…"
        local html token
        html=$(mktemp)
        curl -sS -b "$cookies" -c "$cookies" -o "$html" "${base}/Admin/Plugin/List"
        token=$(extract_token "$html"); rm -f "$html"
        curl -sS -o /dev/null -b "$cookies" -c "$cookies" \
            -X POST "${base}/Admin/Plugin/List" \
            --data-urlencode "__RequestVerificationToken=${token}" \
            --data-urlencode "uninstall-plugin-link-Search.Meilisearch=1" || true
        curl -sS -o /dev/null -b "$cookies" -c "$cookies" \
            -X POST "${base}/Admin/Plugin/List" \
            --data-urlencode "__RequestVerificationToken=${token}" \
            --data-urlencode "plugin-apply-changes=1" || true
        sleep 5
    fi

    local html token code
    html=$(mktemp)
    curl -sS -b "$cookies" -c "$cookies" -o "$html" "${base}/Admin/Plugin/List"
    token=$(extract_token "$html")
    rm -f "$html"
    [ -n "$token" ] || { echo "FAIL: no token on ${bu} Plugin/List"; return 1; }

    echo "    prepare install"
    code=$(curl -sS -o /dev/null -w '%{http_code}' \
        -b "$cookies" -c "$cookies" \
        -X POST "${base}/Admin/Plugin/List" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "install-plugin-link-Search.Meilisearch=1")
    case "$code" in
        200|302) ;;
        *) echo "FAIL: ${bu} install POST returned HTTP ${code}"; return 1 ;;
    esac

    echo "    apply changes (triggers in-process restart + bulk index)"
    curl -sS -o /dev/null -b "$cookies" -c "$cookies" \
        -X POST "${base}/Admin/Plugin/List" \
        --data-urlencode "__RequestVerificationToken=${token}" \
        --data-urlencode "plugin-apply-changes=1" || true
}

# ── Per-BU theme + store name ─────────────────────────────────────────────
configure_bu bu1 "HomeStyle — Northstar Living"
configure_bu bu2 "WorkSpace — Northstar Professionals"

# ── Seed products (must happen before Meilisearch plugin install) ─────────
seed_bu_products bu1
seed_bu_products bu2

# Phase A: prepare + apply install for all plugins on both BUs.
install_keycloak_plugin bu1 8081
install_keycloak_plugin bu2 8082
install_outbox_plugin bu1
install_outbox_plugin bu2
install_erp_plugin bu1 8081
install_erp_plugin bu2 8082
install_meilisearch_plugin bu1 8081
install_meilisearch_plugin bu2 8082

# Phase B: apply-changes triggers an in-process restart; force a clean container
# restart and wait for both storefronts before proceeding with activation.
echo
echo "==> Restarting nop containers so newly installed plugins load"
docker compose restart nop_bu1 nop_bu2 >/dev/null
for port in 8081 8082; do
    if wait_for_storefront "$port"; then
        echo "    :${port} is live"
    else
        echo "FAIL: :${port} did not return HTTP 200 after plugin restart"
        exit 1
    fi
done

# ── Upload product images via nopCommerce admin API ──────────────────────────
# Uploads each image file, links it to the product by SKU, and sets SeoFilename.
# Idempotent: skips products that already have a picture mapping.
upload_product_images () {
    local bu="$1" host_port="$2"
    local base="http://localhost:${host_port}"
    local db_container="northstar-db_${bu}-1"
    local db_name="nop_${bu}"
    local assets_dir="${SCRIPT_DIR}/../assets/images/${bu}"
    local cookies
    cookies=$(mktemp)
    trap 'rm -f "$cookies"' RETURN

    echo "==> ${bu}: uploading product images"
    admin_login "$bu" "$host_port" "$cookies" "$(bu_email "$bu")" || return 1

    # Each entry: "image_file|SKU|seo_filename"
    local entries=()
    if [ "$bu" = "bu1" ]; then
        entries=(
            "linen-sofa.jpg|HS-SOFA-001|linen-sofa"
            "walnut-coffee-table.jpg|HS-TABLE-001|walnut-coffee-table"
            "rattan-pendant-light.jpg|HS-LIGHT-001|rattan-pendant-light"
            "marble-table-lamp.jpg|HS-LIGHT-002|marble-table-lamp"
        )
    else
        entries=(
            "ergonomic-mesh-chair.jpg|WS-CHAIR-001|ergonomic-mesh-chair"
            "adjustable-standing-desk.jpg|WS-DESK-001|adjustable-standing-desk"
            "27-ultrawide-monitor.jpg|WS-MON-001|27-ultrawide-monitor"
            "cable-management-kit.jpg|WS-ACC-001|cable-management-kit"
        )
    fi

    local html token
    html=$(mktemp)
    curl -sS -b "$cookies" -c "$cookies" -o "$html" "${base}/Admin/Picture/List"
    token=$(extract_token "$html"); rm -f "$html"
    [ -n "$token" ] || { echo "WARN: no token for picture upload, skipping images"; return 0; }

    for entry in "${entries[@]}"; do
        local img_file sku seo
        img_file="${assets_dir}/$(echo "$entry" | cut -d'|' -f1)"
        sku=$(echo "$entry" | cut -d'|' -f2)
        seo=$(echo "$entry" | cut -d'|' -f3)

        # Get product ID by SKU
        local product_id
        product_id=$(docker exec "$db_container" psql -U nop -d "$db_name" -tAc \
            "SELECT \"Id\" FROM \"Product\" WHERE \"Sku\" = '${sku}' AND \"Deleted\" = false LIMIT 1;")
        if [ -z "$product_id" ]; then
            echo "    WARN: product SKU ${sku} not found, skipping"
            continue
        fi

        # Skip if product already has a picture mapping
        local existing
        existing=$(docker exec "$db_container" psql -U nop -d "$db_name" -tAc \
            "SELECT COUNT(*) FROM \"Product_Picture_Mapping\" WHERE \"ProductId\" = ${product_id};")
        if [ "${existing:-0}" -gt 0 ]; then
            echo "    ${sku}: already has image — skipping"
            continue
        fi

        if [ ! -f "$img_file" ]; then
            echo "    WARN: image file not found: ${img_file}"
            continue
        fi

        # Upload image via admin API
        local response pic_id
        response=$(curl -sS -b "$cookies" -c "$cookies" \
            -X POST "${base}/Admin/Picture/AsyncUpload" \
            -H "X-Requested-With: XMLHttpRequest" \
            -F "__RequestVerificationToken=${token}" \
            -F "qqfile=@${img_file}")
        pic_id=$(echo "$response" | jq -r '.pictureId // empty' 2>/dev/null)

        if [ -z "$pic_id" ] || [ "$pic_id" = "null" ]; then
            echo "    WARN: upload failed for ${img_file}: ${response}"
            continue
        fi

        # Set SEO filename on the picture record
        docker exec "$db_container" psql -U nop -d "$db_name" -c \
            "UPDATE \"Picture\" SET \"SeoFilename\" = '${seo}' WHERE \"Id\" = ${pic_id};" >/dev/null

        # Link picture to product
        docker exec "$db_container" psql -U nop -d "$db_name" -c \
            "INSERT INTO \"Product_Picture_Mapping\" (\"ProductId\", \"PictureId\", \"DisplayOrder\")
             VALUES (${product_id}, ${pic_id}, 1)
             ON CONFLICT DO NOTHING;" >/dev/null

        echo "    ${sku} → pic_id=${pic_id} (${seo})"
    done
}

# Phase C: activate the methods/widgets on the now-loaded plugins.
activate_keycloak_method bu1 8081
activate_keycloak_method bu2 8082
activate_erp_widget bu1 8081
activate_erp_widget bu2 8082

# Phase D: upload product images via admin API so they are reproducible on any machine.
upload_product_images bu1 8081
upload_product_images bu2 8082

# Phase E: post-upload DB fixups — assign category pictures + remove default slider banners.
# Must run AFTER upload_product_images so the pic_ids exist.
apply_visual_fixups () {
    local bu="$1"
    local db_container="northstar-db_${bu}-1"
    local db_name="nop_${bu}"

    echo "==> ${bu}: applying visual fixups (category pictures + slider removal)"

    docker exec "$db_container" psql -U nop -d "$db_name" -v ON_ERROR_STOP=1 -c "
    DO \$\$
    BEGIN
        -- ── Remove the default homepage slider (iPhone / Galaxy demo content) ──
        UPDATE \"Setting\" SET \"Value\" = '[]'
        WHERE \"Name\" = 'swipersettings.slides';

        -- ── Assign each category its own product picture ──
        -- Each category has exactly one product; use that product's uploaded picture.
        UPDATE \"Category\" c
        SET \"PictureId\" = ppm.\"PictureId\"
        FROM \"Product_Category_Mapping\" pcm
        JOIN \"Product_Picture_Mapping\" ppm ON ppm.\"ProductId\" = pcm.\"ProductId\"
        WHERE pcm.\"CategoryId\" = c.\"Id\"
          AND ppm.\"PictureId\" IS NOT NULL;

        RAISE NOTICE 'Visual fixups done for this BU';
    END \$\$;
    " 2>&1 | grep -v "^psql\|^DO$"
    echo "    done"
}

apply_visual_fixups bu1
apply_visual_fixups bu2

# Phase F: seed Meilisearch with all product fields including pictureUrls.
# The BulkIndexAsync triggered by plugin install is unreliable on first boot;
# this guarantees the portal at :8000 shows real products on every clean run.
# pic_ids are always 3-6 (first 2 are system banners, then products in insert order).
seed_meilisearch () {
    local meili="${MEILI_URL:-http://localhost:7700}"
    local key="${MEILI_KEY:-northstar-meili-master-key}"

    echo "==> Seeding Meilisearch index (all 8 products + pictureUrls)"

    # Ensure index + filterable attribute
    curl -s -o /dev/null -X POST "${meili}/indexes" \
        -H "Authorization: Bearer ${key}" -H "Content-Type: application/json" \
        -d '{"uid":"products","primaryKey":"id"}' || true
    curl -s -o /dev/null -X PATCH "${meili}/indexes/products/settings/filterable-attributes" \
        -H "Authorization: Bearer ${key}" -H "Content-Type: application/json" \
        -d '["buId"]'

    curl -s -o /dev/null -X POST "${meili}/indexes/products/documents?primaryKey=id" \
        -H "Authorization: Bearer ${key}" -H "Content-Type: application/json" \
        -d '[
          {"id":"bu1-1","productId":1,"buId":"bu1","name":"Linen Sofa","description":"Handcrafted 3-seater sofa with solid oak legs.","sku":"HS-SOFA-001","slug":"linen-sofa","price":1249.00,"pictureUrl":"http://localhost:8081/images/thumbs/0000003_linen-sofa_415.jpeg"},
          {"id":"bu1-2","productId":2,"buId":"bu1","name":"Walnut Coffee Table","description":"Solid walnut top, 120x60 cm.","sku":"HS-TABLE-001","slug":"walnut-coffee-table","price":449.00,"pictureUrl":"http://localhost:8081/images/thumbs/0000004_walnut-coffee-table_415.jpeg"},
          {"id":"bu1-3","productId":3,"buId":"bu1","name":"Rattan Pendant Light","description":"Handwoven rattan lamp, 40 cm diameter.","sku":"HS-LIGHT-001","slug":"rattan-pendant-light","price":129.00,"pictureUrl":"http://localhost:8081/images/thumbs/0000005_rattan-pendant-light_415.jpeg"},
          {"id":"bu1-4","productId":4,"buId":"bu1","name":"Marble Table Lamp","description":"White Carrara marble base with a linen shade.","sku":"HS-LIGHT-002","slug":"marble-table-lamp","price":189.00,"pictureUrl":"http://localhost:8081/images/thumbs/0000006_marble-table-lamp_415.jpeg"},
          {"id":"bu2-1","productId":1,"buId":"bu2","name":"Ergonomic Mesh Chair","description":"Full-mesh back, 4D armrests, lumbar support.","sku":"WS-CHAIR-001","slug":"ergonomic-mesh-chair","price":699.00,"pictureUrl":"http://localhost:8082/images/thumbs/0000003_ergonomic-mesh-chair_415.jpeg"},
          {"id":"bu2-2","productId":2,"buId":"bu2","name":"Adjustable Standing Desk","description":"Electric sit-stand, 140x70 cm bamboo top.","sku":"WS-DESK-001","slug":"adjustable-standing-desk","price":849.00,"pictureUrl":"http://localhost:8082/images/thumbs/0000004_adjustable-standing-desk_415.jpeg"},
          {"id":"bu2-3","productId":3,"buId":"bu2","name":"27\" Ultrawide Monitor","description":"QHD IPS panel, 144 Hz, USB-C 90W PD.","sku":"WS-MON-001","slug":"27-ultrawide-monitor","price":549.00,"pictureUrl":"http://localhost:8082/images/thumbs/0000005_27-ultrawide-monitor_415.jpeg"},
          {"id":"bu2-4","productId":4,"buId":"bu2","name":"Cable Management Kit","description":"Under-desk tray, 10 velcro ties, 3 cable clips.","sku":"WS-ACC-001","slug":"cable-management-kit","price":39.00,"pictureUrl":"http://localhost:8082/images/thumbs/0000006_cable-management-kit_415.jpeg"}
        ]'

    echo "    8 documents upserted"

    # apply_visual_fixups wrote to the DB but nopCommerce caches settings in memory.
    # Restart so the slider change and category picture assignments take effect immediately.
    echo "    restarting nop containers to flush settings cache..."
    docker compose restart nop_bu1 nop_bu2 >/dev/null
    for port in 8081 8082; do
        for _ in $(seq 1 60); do
            [ "$(curl -sS -o /dev/null -w '%{http_code}' "http://localhost:${port}/" 2>/dev/null)" = "200" ] && break
            sleep 2
        done
    done

    # Trigger thumbnail generation at all sizes used by the UI:
    #   _550 → product detail page
    #   _415 → category listing page
    #   _450 → homepage category grid
    echo "    warming thumbnail cache (_415/_450/_550)..."
    for slug in linen-sofa walnut-coffee-table rattan-pendant-light marble-table-lamp; do
        curl -s -o /dev/null "http://localhost:8081/${slug}"
    done
    for slug in furniture lighting; do
        curl -s -o /dev/null "http://localhost:8081/${slug}"
    done
    curl -s -o /dev/null "http://localhost:8081/"
    for slug in ergonomic-mesh-chair adjustable-standing-desk 27-ultrawide-monitor cable-management-kit; do
        curl -s -o /dev/null "http://localhost:8082/${slug}"
    done
    for slug in office-chairs desks-monitors; do
        curl -s -o /dev/null "http://localhost:8082/${slug}"
    done
    curl -s -o /dev/null "http://localhost:8082/"
    echo "    done"
}

seed_meilisearch

echo
echo "nopCommerce installed for BU1 and BU2."
echo "  SSO:           Keycloak (ExternalAuth.Keycloak) active"
echo "  ERP widget:    Misc.ErpIntegration active (circuit breaker + stock banner)"
echo "  Search:        Search.Meilisearch active (federated index + DB fallback)"
echo "Admin logins: BU1: ${ADMIN_EMAIL_BU1} / ${ADMIN_PASSWORD}  |  BU2: ${ADMIN_EMAIL_BU2} / ${ADMIN_PASSWORD}"
echo "Try: ./scripts/test-sso.sh  |  ./scripts/test-erp-failure.sh  |  ./scripts/test-search.sh"
