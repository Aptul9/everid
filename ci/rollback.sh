#!/usr/bin/env bash
set -euo pipefail
BASE=/opt/everid
if test "${1:-previous}" = disable; then
  if test -L "$BASE/app"; then CURRENT=$(readlink -f "$BASE/app"); else CURRENT=$(cat "$BASE/candidate-release"); fi
  case "$CURRENT" in "$BASE"/releases/*) ;; *) exit 1 ;; esac
  export RELEASE=${CURRENT##*/}
  docker compose --project-directory "$CURRENT" --env-file "$BASE/.env" stop web server worker
  test -s /etc/sslh.cfg.pre-everid
  # Remove only the EverID line: restoring the whole backup would drop routes added later by other apps.
  grep -v '"id.everbright.it"' /etc/sslh.cfg > "$BASE/sslh.disabled"
  install -m 644 "$BASE/sslh.disabled" /etc/sslh.cfg
  systemctl restart sslh
  systemctl is-active --quiet sslh
  echo 'EverID disabled; database preserved'
  exit 0
fi
test -s "$BASE/previous-release"
PREVIOUS=$(cat "$BASE/previous-release")
case "$PREVIOUS" in "$BASE"/releases/*) ;; *) exit 1 ;; esac
export RELEASE=${PREVIOUS##*/}
docker compose --project-directory "$PREVIOUS" --env-file "$BASE/.env" up -d --wait --wait-timeout 900 --remove-orphans
ln -sfn "$PREVIOUS" "$BASE/app.next"
mv -Tf "$BASE/app.next" "$BASE/app"
# Database stays in place. Pre-deploy dumps in /opt/everid/backups for a manual restore.
curl --fail --silent --show-error -o /dev/null https://id.everbright.it/-/health/live/
