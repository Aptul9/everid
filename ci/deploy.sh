#!/usr/bin/env bash
set -euo pipefail
umask 077

BASE=/opt/everid
RELEASE=${1:?release SHA required}
[[ "$RELEASE" =~ ^[a-f0-9]{40}$ ]] || exit 1
cd "$BASE"
test -s release.tar.gz
test -s environment.new
install -d -m 700 -o 1000 -g 1000 data
install -d -m 700 postgres releases bin backups
NEXT="$BASE/releases/$RELEASE"
install -d -m 755 "$NEXT"
tar xzf release.tar.gz -C "$NEXT"
chmod -R a+rX "$NEXT"

# The database password and secret key live in the data; a changed value would lock the stack out.
if test -e .env && ! cmp -s .env environment.new; then
  echo 'Deployment configuration changed; use a separately approved configuration change.' >&2
  exit 1
fi
if ! test -e .env; then mv environment.new .env; else rm environment.new; fi
chmod 600 .env
export RELEASE

compose() { docker compose --project-directory "$NEXT" --env-file "$BASE/.env" "$@"; }
compose config --quiet
compose pull --quiet postgresql server worker
compose build --pull web
if test -L app && docker ps --format '{{.Names}}' | grep -qx everid-postgresql-1; then
  readlink -f app > previous-release
  docker exec everid-postgresql-1 pg_dump -U authentik -Fc authentik > "backups/pre-deploy-${RELEASE:0:12}.dump"
  find backups -maxdepth 1 -name 'pre-deploy-*.dump' -printf '%T@ %p\n' | sort -rn | tail -n +4 | cut -d' ' -f2- | xargs -r rm -f
fi
printf '%s\n' "$NEXT" > candidate-release

python3 "$NEXT/ci/routing.py" /etc/sslh.cfg "$BASE/sslh.candidate"
if ! cmp -s /etc/sslh.cfg "$BASE/sslh.candidate"; then
  if ! test -e /etc/sslh.cfg.pre-everid; then
    cp -a /etc/sslh.cfg /etc/sslh.cfg.pre-everid
  fi
  # Only add the new route; all existing routes must remain byte-for-byte present.
  install -m 644 "$BASE/sslh.candidate" /etc/sslh.cfg
  systemctl restart sslh
  systemctl is-active --quiet sslh
fi

compose up -d --wait --wait-timeout 900 --remove-orphans
ln -sfn "$NEXT" app.next
mv -Tf app.next app
compose ps

# Nightly database dump: own unit, started by the shared backup-dati.service, which stays untouched.
install -m 700 "$NEXT/ci/backup.sh" bin/backup.sh
install -m 644 "$NEXT/ci/everid-backup.service" /etc/systemd/system/everid-backup.service
install -d -m 755 /etc/systemd/system/backup-dati.service.d
printf '[Unit]\nWants=everid-backup.service\n' > /etc/systemd/system/backup-dati.service.d/everid.conf
chmod 644 /etc/systemd/system/backup-dati.service.d/everid.conf
systemctl daemon-reload

# Public checks: DNS, certificate, server, and the blueprint (applied by the worker in the background).
curl --fail --silent --show-error --retry 24 --retry-delay 5 --retry-all-errors --max-time 15 -o /dev/null https://id.everbright.it/-/health/live/
for slug in everdrive everpush everfit everflow; do
  curl --fail --silent --show-error --retry 36 --retry-delay 5 --retry-all-errors --max-time 15 \
    "https://id.everbright.it/application/o/$slug/.well-known/openid-configuration" \
    | grep -q "\"issuer\": *\"https://id.everbright.it/application/o/$slug/\""
done
# Forward auth from the docker0 address, as the app Caddy containers call it.
# The embedded outpost learns the proxy providers some seconds after the blueprint: 404 until then.
for _ in $(seq 1 36); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -H 'X-Forwarded-Host: calendar.everbright.it' -H 'X-Forwarded-Proto: https' \
    -H 'X-Forwarded-Uri: /' -H 'X-Forwarded-Method: GET' http://172.17.0.1:9000/outpost.goauthentik.io/auth/caddy)
  case "$code" in 302|401) break ;; esac
  sleep 5
done
case "$code" in 302|401) ;; *) echo "forward auth returned $code" >&2; exit 1 ;; esac
compose logs --tail 10 server worker
echo "Deployment complete: $RELEASE"
