#!/bin/bash

echo "### Ожидание запуска всех контейнеров ###"
sleep 10

echo "### Инициализация Replica Set для Config Server'ов ###"
docker compose exec -T configsrv1 mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configsrv1:27019" },
    { _id: 1, host: "configsrv2:27019" },
    { _id: 2, host: "configsrv3:27019" }
  ]
})
EOF

echo "### Инициализация Replica Set для Shard 1 ###"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})
EOF

echo "### Инициализация Replica Set для Shard 2 ###"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})
EOF

echo "### Ожидание 15 секунд ... ###"
sleep 15

echo "### Добавление шардов в кластер ###"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1-1:27018")
sh.addShard("shard2ReplSet/shard2-1:27018")
EOF

echo "### Включение шардирования для somedb ###"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF

echo "### Создание и шардирование коллекции ###"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.createCollection("helloDoc")
sh.shardCollection("somedb.helloDoc", {"_id": "hashed"})
EOF

echo "### Наполнение БД тестовыми документами ###"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"user"+i})
EOF

echo "### Проверка статуса шардов и реплик ###"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF

###
# Проверка общего количества документов
###
echo "Общее количество документов:"
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

###
# Проверка распределения документов по шардам
###
echo "Количество документов в shard1-1:"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Количество документов в shard1-2:"
docker compose exec -T shard1-2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Количество документов в shard1-3:"
docker compose exec -T shard1-3 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Количество документов в shard2-1:"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Количество документов в shard2-2:"
docker compose exec -T shard2-2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Количество документов в shard2-3:"
docker compose exec -T shard2-3 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
