#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF' | docker compose exec -T router mongosh --quiet --port 27017
use somedb
const bulk = db.helloDoc.initializeUnorderedBulkOp();
for (let i = 0; i < 1500; i++) { bulk.insert({ age: i, name: "user"+i }); }
bulk.execute();
print(db.helloDoc.countDocuments());
EOF

echo "Seed completed" 