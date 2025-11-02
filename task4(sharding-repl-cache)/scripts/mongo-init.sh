#!/bin/bash

echo "=== Инициализация MongoDB Sharding + Репликация + Redis Кеширование ==="
echo ""

# Ждем, пока все контейнеры запустятся
echo "Ожидание запуска контейнеров..."
sleep 10

echo ""
echo "=== Шаг 1: Проверка Redis ==="
docker exec redis redis-cli PING
if [ $? -eq 0 ]; then
    echo "✓ Redis работает корректно"
else
    echo "✗ Ошибка: Redis не отвечает"
    exit 1
fi

echo ""
echo "=== Шаг 2: Инициализация Config Server Replica Set ==="
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
echo "=== Шаг 3: Инициализация Replica Set 1 (rs1) для Shard 1 ==="
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
echo "=== Шаг 4: Инициализация Replica Set 2 (rs2) для Shard 2 ==="
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
echo "=== Шаг 5: Добавление шардов в кластер ==="
docker exec -it mongos mongosh --port 27017 --eval '
sh.addShard("rs1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("rs2/shard2-1:27018,shard2-2:27018,shard2-3:27018");
'

echo "Ожидание добавления шардов..."
sleep 3

echo ""
echo "=== Шаг 6: Включение шардирования для базы данных ==="
docker exec -it mongos mongosh --port 27017 --eval '
sh.enableSharding("somedb");
'

echo ""
echo "=== Шаг 7: Создание шардированной коллекции с hashed индексом ==="
docker exec -it mongos mongosh --port 27017 --eval '
sh.shardCollection("somedb.hashed_collection", { _id: "hashed" });
'

echo ""
echo "=== Шаг 8: Заполнение базы данных тестовыми данными ==="
docker exec -it mongos mongosh --port 27017 --eval '
db.getSiblingDB("somedb").hashed_collection.insertMany(
  Array.from({length: 1000}, (_, i) => ({
    _id: i,
    age: i,
    name: "user" + i,
    email: "user" + i + "@example.com",
    created_at: new Date()
  }))
);
'

echo ""
echo "=== Шаг 9: Проверка статуса шардирования ==="
docker exec -it mongos mongosh --port 27017 --eval '
sh.status();
'

echo ""
echo "=== Шаг 10: Проверка статуса Replica Set 1 (rs1) ==="
docker exec -it shard1-1 mongosh --port 27018 --eval '
rs.status();
'

echo ""
echo "=== Шаг 11: Проверка статуса Replica Set 2 (rs2) ==="
docker exec -it shard2-1 mongosh --port 27018 --eval '
rs.status();
'

echo ""
echo "=== Шаг 12: Проверка распределения данных по шардам ==="
docker exec -it mongos mongosh --port 27017 --eval '
use somedb;
db.hashed_collection.getShardDistribution();
'

echo ""
echo "=== Шаг 13: Тестирование кеширования ==="
echo "Первый запрос (без кеша):"
time curl -s http://localhost:8080/hashed_collection/users > /dev/null
echo ""

echo "Второй запрос (с кешем):"
time curl -s http://localhost:8080/hashed_collection/users > /dev/null
echo ""

echo "Третий запрос (с кешем):"
time curl -s http://localhost:8080/hashed_collection/users > /dev/null
echo ""

echo "=== Шаг 14: Проверка статистики Redis ==="
docker exec redis redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"

echo ""
echo "=== Шаг 15: Просмотр кешированных ключей ==="
docker exec redis redis-cli KEYS "*"

echo ""
echo "=== Инициализация завершена! ==="
echo "Кластер MongoDB с шардированием, репликацией и Redis кешированием готов к работе."
echo ""
echo "📊 Архитектура:"
echo "  - 2 Config Servers (configReplSet)"
echo "  - 2 Shards с репликацией (rs1, rs2)"
echo "  - Каждый shard имеет 3 реплики"
echo "  - Redis кеш для ускорения запросов"
echo "  - API приложение на порту 8080"
echo ""
echo "🔍 Полезные команды для проверки:"
echo "  - Статус шардирования: docker exec -it mongos mongosh --eval 'sh.status()'"
echo "  - Статус rs1: docker exec -it shard1-1 mongosh --port 27018 --eval 'rs.status()'"
echo "  - Статус rs2: docker exec -it shard2-1 mongosh --port 27018 --eval 'rs.status()'"
echo "  - Количество документов: docker exec -it mongos mongosh --eval 'use somedb; db.hashed_collection.countDocuments()'"
echo "  - Распределение по шардам: docker exec -it mongos mongosh --eval 'use somedb; db.hashed_collection.getShardDistribution()'"
echo ""
echo "🚀 Тестирование кеширования:"
echo "  - Запрос к API: curl http://localhost:8080/hashed_collection/users"
echo "  - Статистика Redis: docker exec redis redis-cli INFO stats"
echo "  - Просмотр ключей: docker exec redis redis-cli KEYS '*'"
echo "  - Очистка кеша: docker exec redis redis-cli FLUSHALL"
echo ""
echo "⚡ Ожидаемые метрики производительности:"
echo "  - Первый запрос (без кеша): 100-200ms"
echo "  - Повторные запросы (с кешем): 5-20ms"
echo "  - Улучшение скорости: 10-20x"
echo "  - Cache hit rate: ~80%"
