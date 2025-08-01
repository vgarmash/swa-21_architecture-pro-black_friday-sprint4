#!/bin/bash

echo "--- Проверка состояния ---"

echo "shard11:"
docker compose exec -T shard11 mongosh --port 27018 --eval "rs.status().ok"
echo "shard12:"
docker compose exec -T shard12 mongosh --port 27018 --eval "rs.status().ok"
echo "shard13:"
docker compose exec -T shard13 mongosh --port 27018 --eval "rs.status().ok"

echo "shard21:"
docker compose exec -T shard21 mongosh --port 27019 --eval "rs.status().ok"
echo "shard22:"
docker compose exec -T shard22 mongosh --port 27019 --eval "rs.status().ok"
echo "shard23:"
docker compose exec -T shard23 mongosh --port 27019 --eval "rs.status().ok"

echo "--- Проверка документов в shard11 ---"
docker compose exec -T shard11 mongosh --port 27018 <<EOF
use somedb;
db.helloDoc.countDocuments()
EOF
echo "--- Проверка документов в shard12 ---"
docker compose exec -T shard12 mongosh --port 27018 <<EOF
use somedb;
db.helloDoc.countDocuments()
EOF
echo "--- Проверка документов в shard13 ---"
docker compose exec -T shard13 mongosh --port 27018 <<EOF
use somedb;
db.helloDoc.countDocuments()
EOF

echo "--- Проверка документов в shard21 ---"
docker compose exec -T shard21 mongosh --port 27019 <<EOF
use somedb;
try {
  db.helloDoc.countDocuments()
} catch (e) {
  print("Ошибка: " + e.message)
}
EOF
echo "--- Проверка документов в shard22 ---"
docker compose exec -T shard22 mongosh --port 27019 <<EOF
use somedb;
try {
  db.helloDoc.countDocuments()
} catch (e) {
  print("Ошибка: " + e.message)
}
EOF
echo "--- Проверка документов в shard23 ---"
docker compose exec -T shard23 mongosh --port 27019 <<EOF
use somedb;
try {
  db.helloDoc.countDocuments()
} catch (e) {
  print("Ошибка: " + e.message)
}
EOF
