#!/usr/bin/env bash
#
# Nightly Postgres backup for QuietPlay. Dumps the quietplay database out
# of the running postgres container, gzips it to ~/backups/quietplay/, and
# prunes anything older than 14 days.
#
# Schedule via user crontab:
#   0 4 * * * /Users/adam/dev/quietplay/scripts/backup-postgres.sh >> /tmp/quietplay-backup.log 2>&1

set -euo pipefail

CONTAINER="${QP_POSTGRES_CONTAINER:-quietplay-postgres-1}"
DB_USER="${QP_DB_USER:-quietplay}"
DB_NAME="${QP_DB_NAME:-quietplay}"
DEST="${QP_BACKUP_DIR:-$HOME/backups/quietplay}"
RETENTION_DAYS="${QP_BACKUP_RETENTION_DAYS:-14}"

mkdir -p "$DEST"

stamp=$(date +%Y%m%d-%H%M%S)
out="$DEST/quietplay-$stamp.sql.gz"

docker exec "$CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "$out"

# Prune old backups.
find "$DEST" -maxdepth 1 -name 'quietplay-*.sql.gz' -type f -mtime +"$RETENTION_DAYS" -delete

echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') backup: $out ($(stat -f %z "$out" 2>/dev/null || stat -c %s "$out") bytes)"
