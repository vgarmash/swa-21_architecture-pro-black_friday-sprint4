#!/bin/bash

# Скрипт для автоматической инициализации шардирования MongoDB
# Использование: ./scripts/mongo-init.sh

set -e

echo "================================================"
echo "Инициализация шардирования MongoDB"
echo "================================================"
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка, что docker-compose запущен
log_info "Проверка статуса контейнеров..."
if ! docker-compose ps | grep -q "Up"; then
    log_error "Контейнеры не запущены. Запустите их командой: docker-compose up -d"
    exit 1
fi

log_info "Все контейнеры запущены"
echo ""

# Шаг 1: Инициализация Config Server
log_info "Шаг 1/6: Инициализация Config Server..."
docker-compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
EOF

if [ $? -eq 0 ]; then
    log_info "Config Server инициализирован успешно"
else
    log_error "Ошибка при инициализации Config Server"
    exit 1
fi

log_warn "Ожидание 10 секунд для завершения инициализации..."
sleep 10
echo ""

# Шаг 2: Инициализация Shard 1
log_info "Шаг 2/6: Инициализация Shard 1..."
docker-compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF

if [ $? -eq 0 ]; then
    log_info "Shard 1 инициализирован успешно"
else
    log_error "Ошибка при инициализации Shard 1"
    exit 1
fi

log_warn "Ожидание 10 секунд для завершения инициализации..."
sleep 10
echo ""

# Шаг 3: Инициализация Shard 2
log_info "Шаг 3/6: Инициализация Shard 2..."
docker-compose exec -T shard2 mongosh --port 27020 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [{ _id: 0, host: "shard2:27020" }]
})
EOF

if [ $? -eq 0 ]; then
    log_info "Shard 2 инициализирован успешно"
else
    log_error "Ошибка при инициализации Shard 2"
    exit 1
fi

log_warn "Ожидание 10 секунд для завершения инициализации..."
sleep 10
echo ""

# Шаг 4: Добавление шардов в кластер
log_info "Шаг 4/6: Добавление шардов в кластер..."
docker-compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018")
sh.addShard("shard2ReplSet/shard2:27020")
EOF

if [ $? -eq 0 ]; then
    log_info "Шарды добавлены в кластер успешно"
else
    log_error "Ошибка при добавлении шардов"
    exit 1
fi

log_warn "Ожидание 5 секунд..."
sleep 5
echo ""

# Шаг 5: Включение шардирования для базы данных и коллекции
log_info "Шаг 5/6: Включение шардирования для базы данных и коллекции..."
docker-compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { _id: "hashed" })
EOF

if [ $? -eq 0 ]; then
    log_info "Шардирование включено для somedb.helloDoc"
else
    log_error "Ошибка при включении шардирования"
    exit 1
fi

log_warn "Ожидание 5 секунд..."
sleep 5
echo ""

# Шаг 6: Заполнение базы данных тестовыми данными
log_info "Шаг 6/6: Заполнение базы данных тестовыми данными (1000 документов)..."
docker-compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({
    name: "user" + i,
    age: Math.floor(Math.random() * 100),
    email: "user" + i + "@example.com",
    createdAt: new Date()
  })
}
print("Добавлено документов: " + db.helloDoc.countDocuments())
EOF

if [ $? -eq 0 ]; then
    log_info "База данных заполнена успешно"
else
    log_error "Ошибка при заполнении базы данных"
    exit 1
fi

echo ""
echo "================================================"
log_info "Инициализация завершена успешно!"
echo "================================================"
echo ""

# Вывод статистики
log_info "Статистика распределения данных:"
echo ""

echo "Общее количество документов:"
docker-compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
print("  Всего: " + db.helloDoc.countDocuments())
EOF

echo ""
echo "Количество документов на Shard 1:"
docker-compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
print("  Shard 1: " + db.helloDoc.countDocuments())
EOF

echo ""
echo "Количество документов на Shard 2:"
docker-compose exec -T shard2 mongosh --port 27020 --quiet <<EOF
use somedb
print("  Shard 2: " + db.helloDoc.countDocuments())
EOF

echo ""
echo "================================================"
log_info "Приложение доступно по адресу: http://localhost:8080"
log_info "Swagger документация: http://localhost:8080/docs"
echo "================================================"
