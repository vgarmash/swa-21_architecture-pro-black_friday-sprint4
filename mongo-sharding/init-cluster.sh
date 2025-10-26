#!/bin/bash
#set -e  # Завершить скрипт при любой ошибке

echo "Инициализация MongoDB кластера..."

# Ждем запуска контейнеров
echo "Ожидание запуска контейнеров..."
sleep 10

# Инициализация config серверов
echo "Инициализация config серверов..."
docker exec configsrv1 mongosh --eval '
rs.initiate({
  _id: "configrs",
  configsvr: true,
  members: [
    { _id: 0, host: "configsrv1:27017" },
    { _id: 1, host: "configsrv2:27017" },
    { _id: 2, host: "configsrv3:27017" }
  ]
})'

# Инициализация шарда 1
echo "Инициализация shard1..."
docker exec shard1 mongosh --eval '
rs.initiate({
  _id: "shard1rs",
  members: [
    { _id: 0, host: "shard1:27017" }
  ]
})'

# Инициализация шарда 2
echo "Инициализация shard2..."
docker exec shard2 mongosh --eval '
rs.initiate({
  _id: "shard2rs",
  members: [
    { _id: 0, host: "shard2:27017" }
  ]
})'

# Ждем инициализации replica sets
echo "Ожидание инициализации replica sets..."
sleep 15

# Добавление шардов через mongos
# sh.addShard("shard2rs/shard2a:27017,shard2b:27017");'
echo "Добавление шардов в кластер..."
docker exec mongos1 mongosh --eval '
sh.addShard("shard1rs/shard1:27017");
sh.addShard("shard2rs/shard2:27017");'

sleep 5

# Настройка шардирования
echo "Настройка шардирования для somedb.helloDoc..."
docker exec mongos1 mongosh --eval '
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "_id": "hashed" });'

# Проверка статуса
echo "Проверка статуса кластера..."
docker exec mongos1 mongosh --eval '
sh.status()'

echo "Кластер инициализирован успешно!"
