#!/usr/bin/env bash
# One-time setup of EverID secrets. Run by the owner from a machine with gh logged in as Aptul9:
#   bash ci/set-secrets.sh /c/Users/Samuele/OneDrive/Documents/Vault/02_Areas/_secrets/contabo.md
# Generates every value locally, stores it in GitHub Actions secrets and appends a "## EverID" section
# to the lockbox. Nothing is printed. Refuses to run twice: the deployed .env must never change silently.
set -euo pipefail
umask 077

LOCKBOX=${1:?lockbox path required}
OWNER=Aptul9
HOST=217.76.49.98
KEY=${DEPLOY_KEY_FILE:-$HOME/.ssh/arm-samuele-ssh.key}

test -f "$LOCKBOX" || { echo "lockbox not found: $LOCKBOX" >&2; exit 1; }
if grep -q '^## EverID$' "$LOCKBOX"; then
  echo 'Lockbox already has an EverID section: secrets were set before, nothing changed.' >&2
  exit 1
fi
test -f "$KEY" || { echo "deploy key not found: $KEY" >&2; exit 1; }
known=$(ssh-keygen -F "$HOST" | grep -v '^#' | grep ssh-ed25519 || true)
test -n "$known" || { echo "no ed25519 host key for $HOST in known_hosts" >&2; exit 1; }
gh repo view "$OWNER/everid" --json name > /dev/null

gen() { openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-48; }
put() { printf '%s' "$3" | gh secret set "$2" -R "$OWNER/$1" > /dev/null; echo "set $1 $2"; }

PG_PASS=$(gen)
AUTHENTIK_SECRET_KEY=$(gen)$(gen)
ADMIN=$(gen | cut -c1-24)
declare -A OIDC
for app in everdrive everpush everfit everflow; do OIDC[$app]=$(gen)$(gen); done

put everid PG_PASS "$PG_PASS"
put everid AUTHENTIK_SECRET_KEY "$AUTHENTIK_SECRET_KEY"
put everid EVERID_ADMIN_PASSWORD "$ADMIN"
put everid OIDC_SECRET_EVERDRIVE "${OIDC[everdrive]}"
put everid OIDC_SECRET_EVERPUSH "${OIDC[everpush]}"
put everid OIDC_SECRET_EVERFIT "${OIDC[everfit]}"
put everid OIDC_SECRET_EVERFLOW "${OIDC[everflow]}"
put everid DEPLOY_HOST "$HOST"
put everid DEPLOY_USER root
put everid DEPLOY_KNOWN_HOSTS "$known"
gh secret set DEPLOY_SSH_KEY -R "$OWNER/everid" < "$KEY" > /dev/null && echo "set everid DEPLOY_SSH_KEY"

for app in everdrive everpush everfit everflow; do
  put "$app" OIDC_CLIENT_ID "$app"
  put "$app" OIDC_CLIENT_SECRET "${OIDC[$app]}"
  gh variable set OIDC_ISSUER -R "$OWNER/$app" -b "https://id.everbright.it/application/o/$app/" > /dev/null
  echo "set $app variable OIDC_ISSUER"
done

{
  printf '\n## EverID\n\n'
  printf '| Field | Value |\n|---|---|\n'
  printf '| URL | `https://id.everbright.it`, [[everid]] |\n'
  printf '| Admin | user `aptul`, `aptul4ever@gmail.com` |\n'
  printf '| Admin password | `%s` (initial; changes in EverID are not reflected here) |\n' "$ADMIN"
  printf '| Postgres password | `%s` |\n' "$PG_PASS"
  printf '| AUTHENTIK_SECRET_KEY | `%s` |\n' "$AUTHENTIK_SECRET_KEY"
  for app in everdrive everpush everfit everflow; do
    printf '| OIDC client `%s` secret | `%s` |\n' "$app" "${OIDC[$app]}"
  done
  printf '| GitHub `Aptul9/everid` | secrets PG_PASS, AUTHENTIK_SECRET_KEY, EVERID_ADMIN_PASSWORD, OIDC_SECRET_EVERDRIVE/EVERPUSH/EVERFIT/EVERFLOW, DEPLOY_HOST, DEPLOY_USER=root, DEPLOY_SSH_KEY (`vm-arm-samuele`), DEPLOY_KNOWN_HOSTS |\n'
  printf '| App repos everdrive, everpush, everfit, everflow | secrets OIDC_CLIENT_ID (= slug), OIDC_CLIENT_SECRET; variable OIDC_ISSUER |\n'
  printf '| Runtime | `/opt/everid` (`.env` 600, `postgres/`, `data/`, `backups/`), Caddy `127.0.0.1:4451`, outpost `172.17.0.1:9000`, sslh backup `/etc/sslh.cfg.pre-everid` |\n'
} >> "$LOCKBOX"
echo "lockbox: EverID section appended"
