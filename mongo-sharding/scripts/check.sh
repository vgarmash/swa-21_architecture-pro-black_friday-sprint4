#!/bin/bash

echo "--- Проверка состояния ---"

echo "shard1:"
docker compose exec -T shard1 mongosh --port 27018 --eval "rs.status().ok"

echo "shard2:"
docker compose exec -T shard2 mongosh --port 27019 --eval "rs.status().ok"

echo "--- Проверка документов в shard1 ---"
docker compose exec -T shard1 mongosh --port 27018 <<EOF
use somedb;
db.helloDoc.countDocuments()
EOF

echo "--- Проверка документов в shard2 ---"
docker compose exec -T shard2 mongosh --port 27019 <<EOF
use somedb;
try {
  db.helloDoc.countDocuments()
} catch (e) {
  print("Ошибка: " + e.message)
}
EOF