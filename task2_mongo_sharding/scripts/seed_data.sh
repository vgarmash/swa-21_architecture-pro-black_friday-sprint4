#!/usr/bin/env bash
set -euo pipefail

# дождёмся mongos
while ! docker compose exec -T router mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; do sleep 1; done

# теперь повторим сид и проверку
bash scripts/seed_data.sh
bash scripts/show_repl_stats.sh

# и перезапустим API (на всякий случай)
docker compose restart webapi 