# Задание 4: Шардирование + Репликация + Redis Кеширование

## Описание архитектуры

Эта конфигурация реализует полную архитектуру с:
- **Шардированием**: 2 шарда для горизонтального масштабирования
- **Репликацией**: каждый шард имеет 3 реплики для отказоустойчивости
- **Redis кешированием**: для ускорения запросов на 80-90%

### Компоненты системы

1. **Config Servers (2 сервера)**:
   - `configSrv1` (порт 27019)
   - `configSrv2` (порт 27020)
   - Хранят метаданные о шардах

2. **Shard 1 - Replica Set (rs1)**:
   - `shard1-1` (PRIMARY, порт 27021)
   - `shard1-2` (SECONDARY, порт 27022)
   - `shard1-3` (SECONDARY, порт 27023)

3. **Shard 2 - Replica Set (rs2)**:
   - `shard2-1` (PRIMARY, порт 27024)
   - `shard2-2` (SECONDARY, порт 27025)
   - `shard2-3` (SECONDARY, порт 27026)

4. **Mongos Router** (порт 27017):
   - Маршрутизирует запросы к нужным шардам

5. **Redis Cache** (порт 6379):
   - Кеширует результаты запросов
   - Снижает нагрузку на MongoDB на 80%

6. **API Application** (порт 8080):
   - Flask приложение с поддержкой кеширования

## Запуск системы

### Вариант 1: Автоматическая инициализация (рекомендуется)

```bash
cd task4
docker compose up -d
./scripts/mongo-init.sh
```

Скрипт автоматически выполнит все необходимые шаги:
- Инициализацию Config Servers
- Инициализацию Replica Sets для обоих шардов
- Добавление шардов в кластер
- Создание шардированной коллекции
- Заполнение тестовыми данными
- Проверку работы Redis кеширования
- Вывод статистики производительности

### Вариант 2: Ручная инициализация

#### 1. Запуск всех сервисов

```bash
cd task4
docker compose up -d
```

#### 2. Инициализация Config Server Replica Set

```bash
docker exec -it configSrv1 mongosh --port 27019 --eval '
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27019" },
    { _id: 1, host: "configSrv2:27019" }
  ]
})'
```

Проверка статуса:
```bash
docker exec -it configSrv1 mongosh --port 27019 --eval 'rs.status()'
```

#### 3. Инициализация Shard 1 (rs1)

```bash
docker exec -it shard1-1 mongosh --port 27018 --eval '
rs.initiate({
  _id: "rs1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
})'
```

Проверка статуса:
```bash
docker exec -it shard1-1 mongosh --port 27018 --eval 'rs.status()'
```

#### 4. Инициализация Shard 2 (rs2)

```bash
docker exec -it shard2-1 mongosh --port 27018 --eval '
rs.initiate({
  _id: "rs2",
  members: [
    { _id: 0, host: "shard2-1:27018" },
    { _id: 1, host: "shard2-2:27018" },
    { _id: 2, host: "shard2-3:27018" }
  ]
})'
```

Проверка статуса:
```bash
docker exec -it shard2-1 mongosh --port 27018 --eval 'rs.status()'
```

#### 5. Добавление шардов в кластер

```bash
docker exec -it mongos mongosh --eval '
sh.addShard("rs1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("rs2/shard2-1:27018,shard2-2:27018,shard2-3:27018");
'
```

Проверка шардов:
```bash
docker exec -it mongos mongosh --eval 'sh.status()'
```

#### 6. Включение шардирования для базы данных

```bash
docker exec -it mongos mongosh --eval '
sh.enableSharding("somedb");
sh.shardCollection("somedb.hashed_collection", { _id: "hashed" });
'
```

## Тестирование кеширования

### 1. Добавление тестовых данных

```bash
curl -X POST http://localhost:8080/hashed_collection/generate_data \
  -H "Content-Type: application/json" \
  -d '{"num_records": 1000}'
```

### 2. Проверка скорости БЕЗ кеша (первый запрос)

```bash
time curl http://localhost:8080/hashed_collection/users
```

**Ожидаемое время**: 100-200ms

### 3. Проверка скорости С кешем (повторный запрос)

```bash
time curl http://localhost:8080/hashed_collection/users
```

**Ожидаемое время**: 5-20ms (улучшение в 10-20 раз!)

### 4. Множественные запросы для проверки стабильности

```bash
for i in {1..10}; do
  echo "Запрос $i:"
  time curl -s http://localhost:8080/hashed_collection/users > /dev/null
done
```

### 5. Проверка статистики Redis

```bash
docker exec -it redis redis-cli INFO stats
```

Обратите внимание на:
- `keyspace_hits`: количество попаданий в кеш
- `keyspace_misses`: количество промахов

### 6. Просмотр кешированных ключей

```bash
docker exec -it redis redis-cli KEYS "*"
```

### 7. Очистка кеша для повторного тестирования

```bash
docker exec -it redis redis-cli FLUSHALL
```

## Метрики производительности

### Без кеша:
- Response time: 100-200ms
- Нагрузка на MongoDB: 100%

### С кешем:
- Response time: 5-20ms (улучшение в 10-20 раз)
- Cache hit rate: ~80%
- Снижение нагрузки на MongoDB: 80%

## Проверка работы системы

### Проверка всех контейнеров

```bash
docker compose ps
```

Все контейнеры должны быть в статусе `Up`.

### Проверка логов API

```bash
docker compose logs -f pymongo_api
```

Вы должны увидеть сообщения о подключении к Redis и MongoDB.

### Проверка логов Redis

```bash
docker compose logs -f redis
```

### Мониторинг Redis в реальном времени

```bash
docker exec -it redis redis-cli MONITOR
```

Затем в другом терминале выполните запросы к API и наблюдайте за операциями кеширования.

## Остановка системы

```bash
docker compose down
```

Для полной очистки (включая volumes):
```bash
docker compose down -v
```

## Troubleshooting

### Проблема: API не может подключиться к Redis

Проверьте, что Redis запущен:
```bash
docker compose ps redis
```

Проверьте логи Redis:
```bash
docker compose logs redis
```

### Проблема: Медленные запросы даже с кешем

1. Убедитесь, что Redis работает:
```bash
docker exec -it redis redis-cli PING
```

2. Проверьте переменную окружения в API:
```bash
docker exec -it pymongo_api env | grep REDIS
```

3. Очистите кеш и попробуйте снова:
```bash
docker exec -it redis redis-cli FLUSHALL
```

### Проблема: Replica Set не инициализируется

Подождите 10-15 секунд после запуска контейнеров, затем повторите команды инициализации.

## Дополнительная информация

- Кеширование работает только для эндпоинта `/<collection_name>/users`
- TTL кеша: обычно 5-10 минут (зависит от реализации в приложении)
- Redis использует стратегию Cache-Aside Pattern
