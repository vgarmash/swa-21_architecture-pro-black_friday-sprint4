#!/bin/bash

###
# Документы в Shard1
###

echo Shard1
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
