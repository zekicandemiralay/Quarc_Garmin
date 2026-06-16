#!/usr/bin/env bash
# ============================================================
#  Quarc Garmin — Data Backup
#  Run on the OLD server from the project directory:
#    bash backup.sh
#
#  Creates: ./backup_YYYYMMDD_HHMMSS/
#    garmin.sql         — full PostgreSQL dump (all activity data)
#    garth_tokens/      — Garmin Connect auth tokens
#    .env               — secrets and config
# ============================================================
set -e

BACKUP_DIR="./backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Backing up to $BACKUP_DIR ..."

# Load .env for postgres credentials
if [ -f .env ]; then
  set -a; source .env 2>/dev/null || true; set +a
fi

POSTGRES_DB="${POSTGRES_DB:-garmin}"
POSTGRES_USER="${POSTGRES_USER:-garmin}"

# Find the running postgres container
DB_CONTAINER=$(docker ps -q --filter "label=com.docker.compose.service=db" | head -1)
if [ -z "$DB_CONTAINER" ]; then
  echo "ERROR: db container not running. Start it first: docker compose up -d db"
  exit 1
fi

# PostgreSQL dump
echo "  · Dumping PostgreSQL database ($POSTGRES_DB) ..."
docker exec "$DB_CONTAINER" \
  pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" \
  > "$BACKUP_DIR/garmin.sql"

# Garmin auth tokens
echo "  · Copying garth_tokens ..."
if [ -d "./garth_tokens" ] && [ "$(ls -A ./garth_tokens 2>/dev/null)" ]; then
  cp -r ./garth_tokens "$BACKUP_DIR/garth_tokens"
else
  echo "    (no garth_tokens found — skipping)"
fi

# .env
echo "  · Copying .env ..."
cp .env "$BACKUP_DIR/.env"

# Summary
SQL_SIZE=$(du -sh "$BACKUP_DIR/garmin.sql" | awk '{print $1}')
echo ""
echo "Backup complete: $BACKUP_DIR"
echo "  garmin.sql : $SQL_SIZE"
echo ""
echo "Next: copy this folder to the new server."
echo "  scp -r $BACKUP_DIR user@new-server:~/Quarc_Garmin/"
