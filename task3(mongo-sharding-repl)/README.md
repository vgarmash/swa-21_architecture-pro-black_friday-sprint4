# Задание 3: Репликация MongoDB

## Описание

Данный проект реализует схему MongoDB с шардированием и репликацией согласно `task1_schema2_replication.drawio`. Архитектура включает:

- **2 Config Server** в Replica Set (configReplSet)
- **2 Шарда**, каждый с репликацией:
  - **Replica Set 1 (rs1)**: 3 реплики (shard1-1, shard1-2, shard1-3)
  - **Replica Set 2 (rs2)**: 3 реплики (shard2-1, shard2-2, shard2-3)
- **1 Mongos Router** для маршрутизации запросов
- **API приложение** на Python (pymongo)

## Архитектура

```
Клиенты
   ↓
API (pymongo) :8080
   ↓
Mongos Router :27017
   ↓
   ├─→ Config Servers (configReplSet)
   │   ├─ configSrv1 :27019
   │   └─ configSrv2 :27019
   │
   ├─→ Shard 1 (rs1)
   │   ├─ shard1-1 :27018 (PRIMARY)
   │   ├─ shard1-2 :27018 (SECONDARY)
   │   └─ shard1-3 :27018 (SECONDARY)
   │
   └─→ Shard 2 (rs2)
       ├─ shard2-1 :27018 (PRIMARY)
       ├─ shard2-2 :27018 (SECONDARY)
       └─ shard2-3 :27018 (SECONDARY)
```

## Шаги настройки репликации

### 1. Запуск контейнеров

Запустите все сервисы MongoDB:

```bash
cd task3
docker-compose up -d
```

Проверьте, что все контейнеры запущены:

```bash
docker-compose ps
```

Должны быть запущены 11 контейнеров:
- 2 config servers
- 6 shard servers (2 шарда × 3 реплики)
- 1 mongos router
- 1 API приложение

### 2. Инициализация Config Server Replica Set

Подключитесь к первому config server и инициализируйте replica set:

```bash
docker exec -it configSrv1 mongosh --port 27019
```

Выполните команду инициализации:

```javascript
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27019" },
    { _id: 1, host: "configSrv2:27019" }
  ]
})
```

Проверьте статус:

```javascript
rs.status()
```

Выйдите из mongosh: `exit`

### 3. Инициализация Replica Set 1 (rs1) для Shard 1

Подключитесь к первой реплике первого шарда:

```bash
docker exec -it shard1-1 mongosh --port 27018
```

Инициализируйте replica set:

```javascript
rs.initiate({
  _id: "rs1",
  members: [
    { _id: 0, host: "shard1-1:27018", priority: 2 },
    { _id: 1, host: "shard1-2:27018", priority: 1 },
    { _id: 2, host: "shard1-3:27018", priority: 1 }
  ]
})
```

**Примечание**: `priority: 2` для shard1-1 делает его предпочтительным PRIMARY узлом.

Проверьте статус:

```javascript
rs.status()
```

Выйдите: `exit`

### 4. Инициализация Replica Set 2 (rs2) для Shard 2

Подключитесь к первой реплике второго шарда:

```bash
docker exec -it shard2-1 mongosh --port 27018
```

Инициализируйте replica set:

```javascript
rs.initiate({
  _id: "rs2",
  members: [
    { _id: 0, host: "shard2-1:27018", priority: 2 },
    { _id: 1, host: "shard2-2:27018", priority: 1 },
    { _id: 2, host: "shard2-3:27018", priority: 1 }
  ]
})
```

Проверьте статус:

```javascript
rs.status()
```

Выйдите: `exit`

### 5. Добавление шардов в кластер

Подключитесь к mongos router:

```bash
docker exec -it mongos mongosh --port 27017
```

Добавьте оба шарда:

```javascript
sh.addShard("rs1/shard1-1:27018,shard1-2:27018,shard1-3:27018")
sh.addShard("rs2/shard2-1:27018,shard2-2:27018,shard2-3:27018")
```

Проверьте статус шардирования:

```javascript
sh.status()
```

### 6. Включение шардирования для базы данных

```javascript
sh.enableSharding("somedb")
```

### 7. Создание шардированной коллекции

```javascript
sh.shardCollection("somedb.helloDoc", { age: 1 })
```

### 8. Заполнение базы данных тестовыми данными

```javascript
use somedb
for(var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({age: i, name: "ly" + i})
}
```

Проверьте количество документов:

```javascript
db.helloDoc.countDocuments()
```

Выйдите: `exit`

## Автоматизация

Все вышеперечисленные шаги автоматизированы в скрипте [`mongo-init.sh`](scripts/mongo-init.sh).

Для автоматической настройки выполните:

```bash
cd task3
chmod +x scripts/mongo-init.sh
./scripts/mongo-init.sh
```

Скрипт выполнит:
1. Инициализацию Config Server Replica Set
2. Инициализацию Replica Set 1 (rs1)
3. Инициализацию Replica Set 2 (rs2)
4. Добавление шардов в кластер
5. Включение шардирования для базы данных
6. Создание шардированной коллекции
7. Заполнение тестовыми данными
8. Проверку статуса всех компонентов

## Проверка работы репликации

### Проверка статуса Replica Set 1

```bash
docker exec -it shard1-1 mongosh --port 27018 --eval "rs.status()"
```

### Проверка статуса Replica Set 2

```bash
docker exec -it shard2-1 mongosh --port 27018 --eval "rs.status()"
```

### Тестирование отказоустойчивости

1. Остановите PRIMARY узел одного из шардов:

```bash
docker stop shard1-1
```

2. Проверьте, что произошло автоматическое переключение (failover):

```bash
docker exec -it shard1-2 mongosh --port 27018 --eval "rs.status()"
```

Один из SECONDARY узлов должен стать новым PRIMARY.

3. Запустите остановленный узел обратно:

```bash
docker start shard1-1
```

Он автоматически присоединится к replica set как SECONDARY.

## Проверка распределения данных

Проверьте, как данные распределены между шардами:

```bash
docker exec -it mongos mongosh --port 27017 --eval "use somedb; db.helloDoc.getShardDistribution()"
```

## API приложение

API доступно по адресу: `http://localhost:8080`

Примеры запросов:

```bash
# Получить все документы
curl http://localhost:8080/

# Получить документ по ID
curl http://localhost:8080/item/507f1f77bcf86cd799439011
```

## Полезные команды

### Просмотр логов

```bash
# Логи всех сервисов
docker-compose logs -f

# Логи конкретного сервиса
docker-compose logs -f shard1-1
docker-compose logs -f mongos
```

### Подключение к MongoDB

```bash
# К mongos router
docker exec -it mongos mongosh --port 27017

# К конкретному шарду
docker exec -it shard1-1 mongosh --port 27018
docker exec -it shard2-1 mongosh --port 27018

# К config server
docker exec -it configSrv1 mongosh --port 27019
```

### Остановка и очистка

```bash
# Остановить все контейнеры
docker-compose down

# Остановить и удалить volumes (полная очистка)
docker-compose down -v
```

## Преимущества репликации

1. **Высокая доступность**: При отказе PRIMARY узла автоматически выбирается новый PRIMARY из SECONDARY узлов
2. **Отказоустойчивость**: Данные хранятся на нескольких узлах, защита от потери данных
3. **Масштабирование чтения**: Можно читать данные с SECONDARY узлов, распределяя нагрузку
4. **Резервное копирование**: SECONDARY узлы служат живыми резервными копиями

## Мониторинг

### Проверка состояния кластера

```bash
docker exec -it mongos mongosh --port 27017 --eval "sh.status()"
```

### Проверка состояния replica sets

```bash
# Replica Set 1
docker exec -it shard1-1 mongosh --port 27018 --eval "rs.status()"

# Replica Set 2
docker exec -it shard2-1 mongosh --port 27018 --eval "rs.status()"
```

### Проверка количества документов

```bash
docker exec -it mongos mongosh --port 27017 --eval "use somedb; db.helloDoc.countDocuments()"
```

## Порты

| Сервис | Внешний порт | Внутренний порт |
|--------|--------------|-----------------|
| API | 8080 | 8080 |
| Mongos | 27017 | 27017 |
| ConfigSrv1 | 27019 | 27019 |
| ConfigSrv2 | 27020 | 27019 |
| Shard1-1 | 27021 | 27018 |
| Shard1-2 | 27022 | 27018 |
| Shard1-3 | 27023 | 27018 |
| Shard2-1 | 27024 | 27018 |
| Shard2-2 | 27025 | 27018 |
| Shard2-3 | 27026 | 27018 |

## Troubleshooting

### Проблема: Replica set не инициализируется

**Решение**: Убедитесь, что все контейнеры запущены и доступны. Проверьте логи:

```bash
docker-compose logs shard1-1
```

### Проблема: Шарды не добавляются

**Решение**: Убедитесь, что replica sets инициализированы и все узлы в состоянии SECONDARY или PRIMARY:

```bash
docker exec -it shard1-1 mongosh --port 27018 --eval "rs.status()"
```

### Проблема: Данные не распределяются между шардами

**Решение**: Проверьте, что шардирование включено для коллекции:

```bash
docker exec -it mongos mongosh --port 27017 --eval "use somedb; db.helloDoc.getShardDistribution()"
```

## Дополнительная информация

- [MongoDB Replication Documentation](https://docs.mongodb.com/manual/replication/)
- [MongoDB Sharding Documentation](https://docs.mongodb.com/manual/sharding/)
- [Replica Set Configuration](https://docs.mongodb.com/manual/reference/replica-configuration/)
