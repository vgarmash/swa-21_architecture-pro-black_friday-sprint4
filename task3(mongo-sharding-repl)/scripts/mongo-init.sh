#!/bin/bash

echo "=== Инициализация MongoDB Sharding с Репликацией ==="
echo ""

# Ждем, пока все контейнеры запустятся
echo "Ожидание запуска контейнеров..."
sleep 10

echo ""
echo "=== Шаг 1: Инициализация Config Server Replica Set ==="
docker exec -it configSrv1 mongosh --port 27019 --eval '
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27019" },
    { _id: 1, host: "configSrv2:27019" }
  ]
})
'

echo "Ожидание инициализации Config Server..."
sleep 5

echo ""
echo "=== Шаг 2: Инициализация Replica Set 1 (rs1) для Shard 1 ==="
docker exec -it shard1-1 mongosh --port 27018 --eval '
rs.initiate({
  _id: "rs1",
  members: [
    { _id: 0, host: "shard1-1:27018", priority: 2 },
    { _id: 1, host: "shard1-2:27018", priority: 1 },
    { _id: 2, host: "shard1-3:27018", priority: 1 }
  ]
})
'

echo "Ожидание инициализации Replica Set 1..."
sleep 5

echo ""
echo "=== Шаг 3: Инициализация Replica Set 2 (rs2) для Shard 2 ==="
docker exec -it shard2-1 mongosh --port 27018 --eval '
rs.initiate({
  _id: "rs2",
  members: [
    { _id: 0, host: "shard2-1:27018", priority: 2 },
    { _id: 1, host: "shard2-2:27018", priority: 1 },
    { _id: 2, host: "shard2-3:27018", priority: 1 }
  ]
})
'

echo "Ожидание инициализации Replica Set 2..."
sleep 5

echo ""
echo "=== Шаг 4: Добавление шардов в кластер ==="
docker exec -it mongos mongosh --port 27017 --eval '
sh.addShard("rs1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("rs2/shard2-1:27018,shard2-2:27018,shard2-3:27018");
'

echo "Ожидание добавления шардов..."
sleep 3

echo ""
echo "=== Шаг 5: Включение шардирования для базы данных ==="
docker exec -it mongos mongosh --port 27017 --eval '
sh.enableSharding("somedb");
'

echo ""
echo "=== Шаг 6: Создание шардированной коллекции ==="
docker exec -it mongos mongosh --port 27017 --eval '
sh.shardCollection("somedb.helloDoc", { age: 1 });
'

echo ""
echo "=== Шаг 7: Заполнение базы данных тестовыми данными ==="
docker exec -it mongos mongosh --port 27017 --eval '
db.getSiblingDB("somedb").helloDoc.insertMany(
  Array.from({length: 1000}, (_, i) => ({age: i, name: "ly" + i}))
);
'

echo ""
echo "=== Шаг 8: Проверка статуса шардирования ==="
docker exec -it mongos mongosh --port 27017 --eval '
sh.status();
'

echo ""
echo "=== Шаг 9: Проверка статуса Replica Set 1 (rs1) ==="
docker exec -it shard1-1 mongosh --port 27018 --eval '
rs.status();
'

echo ""
echo "=== Шаг 10: Проверка статуса Replica Set 2 (rs2) ==="
docker exec -it shard2-1 mongosh --port 27018 --eval '
rs.status();
'

echo ""
echo "=== Инициализация завершена! ==="
echo "Кластер MongoDB с шардированием и репликацией готов к работе."
echo ""
echo "Полезные команды для проверки:"
echo "  - Статус шардирования: docker exec -it mongos mongosh --eval 'sh.status()'"
echo "  - Статус rs1: docker exec -it shard1-1 mongosh --port 27018 --eval 'rs.status()'"
echo "  - Статус rs2: docker exec -it shard2-1 mongosh --port 27018 --eval 'rs.status()'"
echo "  - Количество документов: docker exec -it mongos mongosh --eval 'use somedb; db.helloDoc.countDocuments()'"
