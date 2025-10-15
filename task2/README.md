# MongoDB Sharding Project

Проект демонстрирует реализацию шардирования MongoDB с двумя шардами для повышения производительности и масштабируемости.

## Архитектура

Проект использует следующие компоненты:

- **Config Server** (configSrv) - хранит метаданные кластера и информацию о распределении данных
- **Shard 1** (shard1) - первый шард для хранения данных
- **Shard 2** (shard2) - второй шард для хранения данных
- **Mongos Router** (mongos) - маршрутизатор запросов к шардам
- **API Application** (pymongo_api) - FastAPI приложение для работы с MongoDB

```
┌─────────────┐
│ pymongo_api │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   mongos    │ ◄─── Query Router
└──────┬──────┘
       │
       ├──────────────┬──────────────┐
       ▼              ▼              ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│configSrv │   │ shard1   │   │ shard2   │
└──────────┘   └──────────┘   └──────────┘
 Метаданные     Данные 1       Данные 2
```

## Быстрый старт

### 1. Запуск контейнеров

```bash
docker compose up -d
```

Подождите 10-15 секунд, чтобы все контейнеры полностью запустились.

### 2. Инициализация шардирования

Выполните следующие команды последовательно:

#### Шаг 1: Инициализация Config Server

```bash
docker compose exec -T configSrv mongosh --port 27019 --quiet <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "configSrv:27019" }]
})
EOF
```

Подождите 5-10 секунд для завершения инициализации.

#### Шаг 2: Инициализация Shard 1

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [{ _id: 0, host: "shard1:27018" }]
})
EOF
```

Подождите 5-10 секунд для завершения инициализации.

#### Шаг 3: Инициализация Shard 2

```bash
docker compose exec -T shard2 mongosh --port 27020 --quiet <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [{ _id: 0, host: "shard2:27020" }]
})
EOF
```

Подождите 5-10 секунд для завершения инициализации.

#### Шаг 4: Добавление шардов в кластер

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1ReplSet/shard1:27018")
sh.addShard("shard2ReplSet/shard2:27020")
EOF
```

#### Шаг 5: Включение шардирования для базы данных и коллекции

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { _id: "hashed" })
EOF
```

#### Шаг 6: Заполнение базы данных тестовыми данными

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({
    name: "user" + i,
    age: Math.floor(Math.random() * 100),
    email: "user" + i + "@example.com",
    createdAt: new Date()
  })
}
EOF
```

### 3. Автоматическая инициализация (альтернатива)

Вместо выполнения команд вручную, можно использовать скрипт:

```bash
./scripts/mongo-init.sh
```

## Проверка работы

### Проверка через веб-интерфейс

Откройте в браузере:
- **Локально**: http://localhost:8080

Вы увидите информацию о:
- Топологии кластера (должно быть "Sharded")
- Списке шардов
- Количестве документов в коллекциях
- Распределении данных между шардами

### Проверка через командную строку

#### Общее количество документов

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

#### Количество документов на Shard 1

```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

#### Количество документов на Shard 2

```bash
docker compose exec -T shard2 mongosh --port 27020 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

#### Статус шардирования

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status()
EOF
```

## Доступные эндпоинты API

- `GET /` - Информация о кластере и статистика
- `GET /docs` - Swagger документация
- `GET /{collection_name}/count` - Количество документов в коллекции
- `GET /{collection_name}/users` - Список пользователей
- `GET /{collection_name}/users/{name}` - Получить пользователя по имени
- `POST /{collection_name}/users` - Создать нового пользователя

## Остановка и очистка

### Остановка контейнеров

```bash
docker compose down
```

### Полная очистка (включая данные)

```bash
docker compose down -v
```

## Порты

- **27017** - Mongos Router (точка входа для приложений)
- **27018** - Shard 1
- **27019** - Config Server
- **27020** - Shard 2
- **8080** - API приложение

## Технические детали

### Стратегия шардирования

Используется **hashed sharding** по полю `_id`:
```javascript
sh.shardCollection("somedb.helloDoc", { _id: "hashed" })
```

Это обеспечивает равномерное распределение данных между шардами.

### База данных и коллекция

- **База данных**: `somedb`
- **Коллекция**: `helloDoc`
- **Минимальное количество документов**: 1000

### Replica Sets

Каждый компонент работает как replica set (даже с одним узлом):
- `configReplSet` - для Config Server
- `shard1ReplSet` - для Shard 1
- `shard2ReplSet` - для Shard 2

Это необходимо для работы шардирования в MongoDB.
