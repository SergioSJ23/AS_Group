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

ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"

# Detect admin email per-BU from the database (first non-system account).
detect_admin_email () {
    local db_container="$1" db_name="$2"
    docker exec "$db_container" psql -U nop -d "$db_name" -tAc \
        "SELECT \"Email\" FROM \"Customer\" WHERE \"IsSystemAccount\" = false AND \"Email\" IS NOT NULL ORDER BY \"Id\" LIMIT 1;" 2>/dev/null | tr -d '[:space:]'
}

ADMIN_EMAIL_BU1=$(detect_admin_email "northstar-db_bu1-1" "nop_bu1")
ADMIN_EMAIL_BU2=$(detect_admin_email "northstar-db_bu2-1" "nop_bu2")
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

# nopCommerce's in-process "restart host" doesn't reliably reload appsettings in Docker,
# so force a container restart to make both BUs pick up their new connection strings.
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

# Helpers for the admin flow: log in as the admin, drive plugin install + activation.
# The plugin list page reuses POST /Admin/Plugin/List with form fields that match the
# [FormValueRequired(StartsWith, "install-plugin-link-")] dispatcher.

extract_token () {
    grep -oE 'name="__RequestVerificationToken"[^>]*value="[^"]+"' "$1" \
        | head -1 \
        | sed -E 's/.*value="([^"]+)".*/\1/'
}

bu_email () {
    if [ "$1" = "bu1" ]; then echo "$ADMIN_EMAIL_BU1"; else echo "$ADMIN_EMAIL_BU2"; fi
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
        *) echo "FAIL: ${bu} login POST returned HTTP ${code} (email=${email})"; return 1 ;;
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

# Phase A: prepare + apply install for all plugins on both BUs.
install_keycloak_plugin bu1 8081
install_keycloak_plugin bu2 8082
install_erp_plugin bu1 8081
install_erp_plugin bu2 8082

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

# Phase C: activate the methods/widgets on the now-loaded plugins.
activate_keycloak_method bu1 8081
activate_keycloak_method bu2 8082
activate_erp_widget bu1 8081
activate_erp_widget bu2 8082

echo
echo "nopCommerce installed for BU1 and BU2."
echo "  SSO:          Keycloak (ExternalAuth.Keycloak) active"
echo "  ERP widget:   Misc.ErpIntegration active (circuit breaker + stock banner)"
echo "Admin logins: BU1: ${ADMIN_EMAIL_BU1} / ${ADMIN_PASSWORD}  |  BU2: ${ADMIN_EMAIL_BU2} / ${ADMIN_PASSWORD}"
echo "Try: ./scripts/test-sso.sh  |  ./scripts/test-erp-failure.sh"
