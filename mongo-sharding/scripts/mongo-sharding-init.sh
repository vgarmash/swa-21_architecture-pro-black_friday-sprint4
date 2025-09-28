#!/bin/bash

###
# Инициализация Replica Set для Config Server'а
###

docker compose exec -T configsrv1 mongosh --port 27019 --quiet <<EOF
rs.initiate({_id: "configReplSet", configsvr: true, members: [{_id: 0, host: "configsrv1:27019"}]})
EOF

###
# Инициализация Replica Set для Shard 1
###

docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard1ReplSet", members: [{_id: 0, host: "shard1:27018"}]})
EOF

###
# Инициализация Replica Set для Shard 2
###

docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
rs.initiate({_id: "shard2ReplSet", members: [{_id: 0, host: "shard2:27018"}]})
EOF

###
# Ожидание инициализации реплик
###

echo "Ожидание 10 секунд инициализации Replica Sets..."
sleep 10

###
# Добавление шардов в кластер
###

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018")
sh.addShard("shard2ReplSet/shard2:27018")
EOF

###
# Включение шардирования для БД somedb
###

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
EOF

###
# Создание и шардирование коллекции
###

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.createCollection("helloDoc")
sh.shardCollection("somedb.helloDoc", {"_id": "hashed"})
EOF

###
# Наполнение БД тестовыми документами
###

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
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
echo "Количество документов в 1-м шарде:"
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF

echo "Количество документов во 2-м шарде:"
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
