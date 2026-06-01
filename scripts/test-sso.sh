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
BU1_SECRET="bu1-secret"
BU2_SECRET="bu2-secret"
BU1_REDIRECT="http://bu1.localtest.me:8081/signin-keycloak"
BU2_REDIRECT="http://bu2.localtest.me:8082/signin-keycloak"
USERNAME="alice"
PASSWORD="alice123"
# Expected per-BU client roles (assigned to alice on BOTH clients in the realm).
BU1_ROLE="HomeStyle-VIP"
BU2_ROLE="WorkSpace-Wholesale"

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

# Pull the ?code=... value out of a redirect URL.
extract_code () {
    printf '%s' "$1" | sed -nE 's/.*[?&]code=([^&]+).*/\1/p'
}

# Exchange an authorization code for tokens and print the bu_roles claim, one role per line.
# Reads the access_token's "bu_roles" array (the per-client role mapper output).
bu_roles () {
    local client_id="$1" secret="$2" redirect_uri="$3" code="$4"
    curl -sS -X POST \
        --data-urlencode "grant_type=authorization_code" \
        --data-urlencode "client_id=$client_id" \
        --data-urlencode "client_secret=$secret" \
        --data-urlencode "redirect_uri=$redirect_uri" \
        --data-urlencode "code=$code" \
        "$KC_BASE/realms/$REALM/protocol/openid-connect/token" \
    | python3 -c '
import sys, json, base64
tok = json.load(sys.stdin).get("access_token", "")
if not tok:
    sys.exit(0)
payload = tok.split(".")[1]
payload += "=" * (-len(payload) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload))
for r in claims.get("bu_roles", []):
    print(r)
'
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
        BU1_CODE=$(extract_code "$redir")
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
        BU2_CODE=$(extract_code "$redir")
        echo
        echo "SSO VERIFIED: single login → tokens for BU1 and BU2"
        ;;
    *)
        echo "FAIL: expected silent redirect to BU2 with ?code=..., got: $redir"
        exit 1
        ;;
esac

echo
echo "==> 4. Role isolation: assert zero role bleed-through across BUs"
BU1_ROLES=$(bu_roles "$BU1_CLIENT" "$BU1_SECRET" "$BU1_REDIRECT" "$BU1_CODE")
BU2_ROLES=$(bu_roles "$BU2_CLIENT" "$BU2_SECRET" "$BU2_REDIRECT" "$BU2_CODE")
echo "    BU1 token bu_roles: $(echo "$BU1_ROLES" | paste -sd, -)"
echo "    BU2 token bu_roles: $(echo "$BU2_ROLES" | paste -sd, -)"

has_role () { echo "$1" | grep -qx "$2"; }

fail=0
has_role "$BU1_ROLES" "$BU1_ROLE"  || { echo "FAIL: BU1 token missing its own role $BU1_ROLE"; fail=1; }
has_role "$BU1_ROLES" "$BU2_ROLE"  && { echo "FAIL: BU1 token LEAKED BU2 role $BU2_ROLE"; fail=1; }
has_role "$BU2_ROLES" "$BU2_ROLE"  || { echo "FAIL: BU2 token missing its own role $BU2_ROLE"; fail=1; }
has_role "$BU2_ROLES" "$BU1_ROLE"  && { echo "FAIL: BU2 token LEAKED BU1 role $BU1_ROLE"; fail=1; }
if [ "$fail" -ne 0 ]; then
    echo "ROLE BLEED-THROUGH DETECTED — QA3 not satisfied"
    exit 1
fi
echo "    OK — each BU token carries only its own role (alice holds both in Keycloak)"
echo
echo "ROLE ISOLATION VERIFIED: zero role bleed-through (QA3)"
