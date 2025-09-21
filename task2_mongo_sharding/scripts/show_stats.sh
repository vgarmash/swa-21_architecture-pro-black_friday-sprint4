#!/usr/bin/env bash
set -euo pipefail

echo "== Total documents and listShards =="
cat <<'EOF' | docker compose exec -T router mongosh --quiet --port 27017
use somedb
print("Total:", db.helloDoc.countDocuments({}))
printjson(db.adminCommand({listShards:1}))
EOF

echo "== Sharding status =="
docker compose exec -T router mongosh --quiet --port 27017 --eval 'sh.status()' | sed -n '1,120p' 