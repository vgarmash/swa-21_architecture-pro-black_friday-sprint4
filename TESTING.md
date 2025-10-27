# Руководство по запуску и проверке

> 🧪 Пошаговое руководство для запуска и тестирования MongoDB Sharding  
> 🏠 [← Вернуться к README](README.md) | ⚙️ [Подробная настройка →](SHARDING_SETUP.md)

## Быстрый старт (5 минут)

### 1. Запуск всех сервисов

```bash
cd /Users/nspeganov/IdeaProjects/mongodb-sharding-optimization
docker compose up -d
```

**Ожидайте запуска всех 7 контейнеров:**
- ✅ configSrv1, configSrv2, configSrv3
- ✅ shard1, shard2
- ✅ mongos
- ✅ pymongo-api

**Проверка запуска:**
```bash
docker compose ps
```

Все контейнеры должны быть в статусе `running`.

### 2. Инициализация шардирования

```bash
./scripts/init-sharding.sh
```

**Скрипт выполнит:**
1. Инициализацию Config Server Replica Set
2. Инициализацию Shard 1 и Shard 2 Replica Sets
3. Добавление шардов в кластер
4. Включение шардирования для БД `somedb`
5. Создание и шардирование коллекции `helloDoc`
6. Загрузку 1000 документов
7. Проверку распределения данных

**Время выполнения:** ~1-2 минуты

### 3. Проверка результата

```bash
curl http://localhost:8080 | jq
```

**Ожидаемый результат:**
```json
{
  "mongo_topology_type": "Sharded",
  "mongo_is_mongos": true,
  "mongo_db": "somedb",
  "collections": {
    "helloDoc": {
      "documents_count": 1000
    }
  },
  "shards": {
    "shard1ReplSet": "shard1ReplSet/shard1:27018",
    "shard2ReplSet": "shard2ReplSet/shard2:27018"
  },
  "shard_distribution": {
    "helloDoc": {
      "shard1ReplSet": {
        "count": 500,
        "size": 45000
      },
      "shard2ReplSet": {
        "count": 500,
        "size": 45000
      }
    }
  },
  "status": "OK"
}
```

## Подробная проверка

### Проверка 1: Статус контейнеров

```bash
docker compose ps
```

**Ожидаемый вывод:**
```
NAME         IMAGE                                 STATUS
configSrv1   dh-mirror.gitverse.ru/mongo:latest   Up
configSrv2   dh-mirror.gitverse.ru/mongo:latest   Up
configSrv3   dh-mirror.gitverse.ru/mongo:latest   Up
mongos       dh-mirror.gitverse.ru/mongo:latest   Up
pymongo-api  mongo-sharding-pymongo-api           Up
shard1       dh-mirror.gitverse.ru/mongo:latest   Up
shard2       dh-mirror.gitverse.ru/mongo:latest   Up
```

### Проверка 2: Topology Type = Sharded

```bash
curl -s http://localhost:8080 | jq '.mongo_topology_type'
```

**Ожидается:** `"Sharded"`

### Проверка 3: Mongos Router

```bash
curl -s http://localhost:8080 | jq '.mongo_is_mongos'
```

**Ожидается:** `true`

### Проверка 4: Количество документов

```bash
curl -s http://localhost:8080 | jq '.collections.helloDoc.documents_count'
```

**Ожидается:** `1000` или больше

### Проверка 5: Список шардов

```bash
curl -s http://localhost:8080 | jq '.shards'
```

**Ожидается:**
```json
{
  "shard1ReplSet": "shard1ReplSet/shard1:27018",
  "shard2ReplSet": "shard2ReplSet/shard2:27018"
}
```

### Проверка 6: Распределение по шардам

```bash
curl -s http://localhost:8080 | jq '.shard_distribution.helloDoc'
```

**Ожидается:** Данные распределены между двумя шардами

```json
{
  "shard1ReplSet": {
    "count": 500,
    "size": 45000
  },
  "shard2ReplSet": {
    "count": 500,
    "size": 45000
  }
}
```

### Проверка 7: Подсчет в каждом шарде

**Shard 1:**
```bash
docker compose exec -T shard1 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Shard 2:**
```bash
docker compose exec -T shard2 mongosh --port 27018 --quiet <<EOF
use somedb
db.helloDoc.countDocuments()
EOF
```

**Ожидается:** Сумма документов в обоих шардах = 1000

### Проверка 8: Статус шардирования

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.status();
EOF
```

**В выводе должно быть:**
- ✅ 2 шарда (shard1ReplSet, shard2ReplSet)
- ✅ База данных `somedb` с шардированием
- ✅ Коллекция `somedb.helloDoc` распределена

### Проверка 9: Браузер

Откройте http://localhost:8080 в браузере

**Вы должны увидеть JSON с:**
- `"mongo_topology_type": "Sharded"`
- `"mongo_is_mongos": true`
- `"status": "OK"`
- Информацию о шардах и распределении

### Проверка 10: Swagger UI

Откройте http://localhost:8080/docs

**Доступные endpoints:**
- `GET /` - Общая информация о кластере
- `GET /{collection_name}/count` - Количество документов
- `GET /{collection_name}/users` - Список пользователей
- `GET /{collection_name}/users/{name}` - Конкретный пользователь
- `POST /{collection_name}/users` - Создание пользователя

## Тестирование API

### Получить количество документов

```bash
curl http://localhost:8080/helloDoc/count
```

**Ответ:**
```json
{
  "status": "OK",
  "mongo_db": "somedb",
  "items_count": 1000
}
```

### Получить список пользователей

```bash
curl http://localhost:8080/helloDoc/users | jq '.users | length'
```

**Ответ:** `1000`

### Найти конкретного пользователя

```bash
curl http://localhost:8080/helloDoc/users/ly42
```

**Ответ:**
```json
{
  "age": 42,
  "name": "ly42"
}
```

### Создать нового пользователя

```bash
curl -X POST http://localhost:8080/helloDoc/users \
  -H "Content-Type: application/json" \
  -d '{"age": 99, "name": "testuser"}'
```

**Ответ:**
```json
{
  "_id": "...",
  "age": 99,
  "name": "testuser"
}
```

## Проверка производительности

### Тест вставки данных

```bash
time docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
for(var i = 1000; i < 2000; i++) {
  db.helloDoc.insertOne({age: i, name: "user" + i});
}
EOF
```

### Тест чтения

```bash
time curl -s http://localhost:8080/helloDoc/users > /dev/null
```

### Проверка распределения после добавления данных

```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.getShardDistribution();
EOF
```

## Критерии успешного прохождения

### Задание 2 считается выполненным, если:

- ✅ **Проект запускается** без ошибок
- ✅ **Все контейнеры работают** (7 контейнеров)
- ✅ **Инициализация проходит без ошибок**
- ✅ **Topology Type = "Sharded"**
- ✅ **mongo_is_mongos = true**
- ✅ **В БД ≥ 1000 документов**
- ✅ **2 шарда добавлены в кластер**
- ✅ **Данные распределены между шардами**
- ✅ **API возвращает информацию о шардах**
- ✅ **shard_distribution показывает количество документов в каждом шарде**

## Очистка и перезапуск

### Остановка без удаления данных

```bash
docker compose down
```

### Полная очистка (удаление данных)

```bash
docker compose down -v
```

### Перезапуск с нуля

```bash
docker compose down -v
docker compose up -d
sleep 10
./scripts/init-sharding.sh
```

## Просмотр логов

### Все сервисы

```bash
docker compose logs -f
```

### Конкретный сервис

```bash
docker compose logs -f mongos
docker compose logs -f shard1
docker compose logs -f pymongo-api
```

### Последние 100 строк

```bash
docker compose logs --tail=100 mongos
```

## Устранение проблем

### Проблема: Контейнеры не запускаются

```bash
docker compose down -v
docker compose up -d
```

### Проблема: Порт 8080 занят

Проверьте занятые порты:
```bash
lsof -i :8080
```

Измените порт в `compose.yaml`:
```yaml
ports:
  - "8081:8080"  # Используйте другой порт
```

### Проблема: "Connection refused"

Подождите 10-15 секунд после `docker compose up -d` для полного запуска MongoDB.

### Проблема: Данные не распределяются

Убедитесь, что:
1. Коллекция была шардирована **до** вставки данных
2. Используется правильный shard key (`{ _id: "hashed" }`)

Пересоздайте коллекцию:
```bash
docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
use somedb
db.helloDoc.drop();
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i});
}
db.helloDoc.getShardDistribution();
EOF
```

## Следующие шаги

После успешной проверки переходите к следующим заданиям:
- 📖 [Задание 3: Репликация](REPLICATION_SETUP.md)
- 📖 [Задание 4: Кеширование](CACHING_SETUP.md)

## Полезные ссылки

- 🏠 [Главная документация](README.md)
- ⚙️ [Подробная настройка шардирования](SHARDING_SETUP.md)
- 📊 [Схемы архитектуры](diagrams/ARCHITECTURE.md)
- 📖 [Планирование](PLANNING.md)

