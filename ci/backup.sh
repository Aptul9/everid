#!/usr/bin/env bash
# Nightly EverID backup, started with backup-dati.service (03:30). pg_dump custom format, then
# pg_restore --list proves the archive is readable. Last 3 kept next to the other VM archives.
set -euo pipefail
umask 077
OUT=/var/backups/vm-dati
install -d -m 700 "$OUT"
stamp=$(date +%F)
archive="$OUT/everid-$stamp.dump"
docker exec everid-postgresql-1 pg_dump -U authentik -Fc authentik > "$archive.part"
docker exec -i everid-postgresql-1 pg_restore --list < "$archive.part" > /dev/null
mv "$archive.part" "$archive"
sha256sum "$archive" > "$archive.sha256"
find "$OUT" -maxdepth 1 -name 'everid-*.dump' -printf '%T@ %p\n' | sort -rn | tail -n +4 | cut -d' ' -f2- | while read -r old; do
  rm -f "$old" "$old.sha256"
done
echo "everid backup: $archive $(du -h "$archive" | cut -f1), list check ok"
