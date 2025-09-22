#!/usr/bin/env bash
set -euo pipefail

echo "== Total documents and listShards =="
cat <<'EOF' | docker compose exec -T router mongosh --quiet --port 27017
use somedb
print("Total:", db.helloDoc.countDocuments({}))
printjson(db.adminCommand({listShards:1}))
EOF

echo "== Replica members rsA =="
docker compose exec -T shard_a1 mongosh --quiet --port 27018 --eval 'rs.status().members.map(m=>({id:m._id,name:m.name,stateStr:m.stateStr}))'

echo "== Replica members rsB =="
docker compose exec -T shard_b1 mongosh --quiet --port 27019 --eval 'rs.status().members.map(m=>({id:m._id,name:m.name,stateStr:m.stateStr}))'

# Short sh.status excerpt
echo "== Sharding status (short) =="
docker compose exec -T router mongosh --quiet --port 27017 --eval 'sh.status()' | sed -n '1,120p' 