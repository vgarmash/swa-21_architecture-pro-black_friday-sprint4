#!/bin/bash

###
# Документы в Shard2
###

echo "\nShard2 (MASTER)";
docker compose exec -T shard2_1 mongosh --port 27021 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "\nShard2 (REPLICA1)"
docker compose exec -T shard2_2 mongosh --port 27022 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "\nShard2 (REPLICA2)"
docker compose exec -T shard2_3 mongosh --port 27023 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
