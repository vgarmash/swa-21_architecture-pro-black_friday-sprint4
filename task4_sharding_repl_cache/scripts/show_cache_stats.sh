#!/usr/bin/env bash
set -euo pipefail

# DB stats
cat <<'EOF' | docker compose exec -T router mongosh --quiet --port 27017
use somedb
print("Total:", db.helloDoc.countDocuments({}))
printjson(db.adminCommand({listShards:1}))
EOF

# Quick API timing (first vs second call) to see cache effect
API=http://localhost:8082/helloDoc/users

echo "== First call (cold) =="
/usr/bin/time -f '%E' curl -s -o /dev/null "$API" || true

echo "== Second call (warm, expect <100ms) =="
/usr/bin/time -f '%E' curl -s -o /dev/null "$API" || true 