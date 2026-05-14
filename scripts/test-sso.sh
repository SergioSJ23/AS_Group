#!/usr/bin/env bash
# ADR-002 SSO smoke test.
#
# Verifies that one Keycloak login produces authorization codes for BOTH BU1 and BU2
# without re-prompting for credentials.
#
# Flow:
#   1. Start the authorization code flow for bu1-nopcommerce → Keycloak login form.
#   2. POST alice/alice123 to the form action URL. Expect a 302 to BU1's /signin-keycloak
#      with ?code=...; Keycloak also drops an SSO session cookie on keycloak.localtest.me.
#   3. Reuse the cookie jar to start the authorization code flow for bu2-nopcommerce.
#      With SSO working, Keycloak skips the login form and 302s straight to BU2 with a code.
#
# Run from the repo root after `docker compose up`. Requires curl.

set -euo pipefail

KC_BASE="http://keycloak.localtest.me:8080"
REALM="northstar"
BU1_CLIENT="bu1-nopcommerce"
BU2_CLIENT="bu2-nopcommerce"
BU1_REDIRECT="http://bu1.localtest.me:8081/signin-keycloak"
BU2_REDIRECT="http://bu2.localtest.me:8082/signin-keycloak"
USERNAME="alice"
PASSWORD="alice123"

COOKIES=$(mktemp)
trap 'rm -f "$COOKIES"' EXIT

authorize () {
    local client_id="$1" redirect_uri="$2"
    curl -sS -G \
        -c "$COOKIES" -b "$COOKIES" \
        --data-urlencode "client_id=$client_id" \
        --data-urlencode "response_type=code" \
        --data-urlencode "scope=openid" \
        --data-urlencode "redirect_uri=$redirect_uri" \
        --data-urlencode "state=sso-test-$client_id" \
        "$KC_BASE/realms/$REALM/protocol/openid-connect/auth"
}

echo "==> 1. Fetch Keycloak login page for $BU1_CLIENT"
login_html=$(authorize "$BU1_CLIENT" "$BU1_REDIRECT")
form_action=$(printf '%s' "$login_html" \
    | grep -oE 'action="[^"]+login-actions/authenticate[^"]*"' \
    | head -1 \
    | sed -E 's/^action="([^"]+)"$/\1/; s/&amp;/\&/g')
if [ -z "$form_action" ]; then
    echo "FAIL: could not locate the login form action URL — is Keycloak healthy?"
    exit 1
fi
echo "    form action: ${form_action:0:80}..."

echo "==> 2. POST credentials for $USERNAME"
result=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' \
    -c "$COOKIES" -b "$COOKIES" \
    --data-urlencode "username=$USERNAME" \
    --data-urlencode "password=$PASSWORD" \
    --data-urlencode "credentialId=" \
    "$form_action")
http=${result%% *}
redir=${result#* }
if [ "$http" != "302" ]; then
    echo "FAIL: expected 302 after credential POST, got $http"
    echo "      Keycloak likely rejected the credentials."
    exit 1
fi
case "$redir" in
    *bu1.localtest.me:8081/signin-keycloak*code=*)
        echo "    OK — Keycloak issued a code for BU1"
        ;;
    *)
        echo "FAIL: expected redirect to BU1 with ?code=..., got: $redir"
        exit 1
        ;;
esac

echo "==> 3. Re-authorize for $BU2_CLIENT using the same cookie jar (SSO probe)"
result=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' \
    -c "$COOKIES" -b "$COOKIES" \
    -G \
    --data-urlencode "client_id=$BU2_CLIENT" \
    --data-urlencode "response_type=code" \
    --data-urlencode "scope=openid" \
    --data-urlencode "redirect_uri=$BU2_REDIRECT" \
    --data-urlencode "state=sso-test-$BU2_CLIENT" \
    "$KC_BASE/realms/$REALM/protocol/openid-connect/auth")
http=${result%% *}
redir=${result#* }
if [ "$http" != "302" ]; then
    echo "FAIL: expected silent 302 for BU2, got $http — SSO is NOT working"
    echo "      (Keycloak likely returned the login form again.)"
    exit 1
fi
case "$redir" in
    *bu2.localtest.me:8082/signin-keycloak*code=*)
        echo "    OK — Keycloak issued a code for BU2 without re-prompt"
        echo
        echo "SSO VERIFIED: single login → tokens for BU1 and BU2"
        ;;
    *)
        echo "FAIL: expected silent redirect to BU2 with ?code=..., got: $redir"
        exit 1
        ;;
esac
