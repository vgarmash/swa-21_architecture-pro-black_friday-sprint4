#!/bin/bash

###
# Документы в Shard1
###

echo "Shard1 (MASTER)"
docker compose exec -T shard1_1 mongosh --port 27011 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Shard1 (REPLICA1)"
docker compose exec -T shard1_2 mongosh --port 27012 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Shard1 (REPLICA2)"
docker compose exec -T shard1_3 mongosh --port 27013 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
