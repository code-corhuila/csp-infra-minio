#!/usr/bin/env sh
# Creates the shared network (idempotent), brings the storage of an environment up, waits until it is healthy and runs
# the setup job (bucket, rules and accounts). Usage: ./scripts/up.sh dev|qa|main
set -eu
cd "$(dirname "$0")/.."
env_name="${1:?usage: up.sh dev|qa|main}"
env_file="env/$env_name.env"
[ -f "$env_file" ] || { echo "missing $env_file: cp env/$env_name.env.example $env_file and fill it in"; exit 1; }
for name in RUSTFS_ROOT_USER RUSTFS_ROOT_PASSWORD TICKETING_PDF_WRITER_SECRET TICKETING_PDF_READER_SECRET; do
  grep -q "^$name=." "$env_file" || { echo "$name is empty in $env_file: openssl rand -hex 24"; exit 1; }
done
# the console is published (to the loopback) only in dev
[ "$env_name" = dev ] && COMPOSE_FILE=compose.yml:compose.dev.yml || COMPOSE_FILE=compose.yml
export COMPOSE_FILE COMPOSE_PATH_SEPARATOR=:
docker network inspect platform >/dev/null 2>&1 || docker network create platform
docker compose --env-file "$env_file" up -d --wait rustfs
docker compose --env-file "$env_file" run --rm -T setup < rustfs/setup.sh
docker compose --env-file "$env_file" ps
