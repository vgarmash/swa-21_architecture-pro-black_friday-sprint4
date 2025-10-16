# MongoDB Sharding

Стенд `mongo-sharding` демонстрирует базовую конфигурацию MongoDB с шардингом. Каждый шард представлен одним узлом, что позволяет сосредоточиться на горизонтальном распределении данных и работе балансировщика без усложнения отказоустойчивости. Этот README служит общим руководством: стенд `mongo-sharding-repl` с репликацией ссылается на те же команды и сценарии.

## Архитектура

### Config Server Replica Set (3 узла)
- `configSrv-1:27019` — Config Server 1
- `configSrv-2:27019` — Config Server 2
- `configSrv-3:27019` — Config Server 3

### Shard 1 (standalone replica set)
- `shard1-1:27018` — единственный узел `shard1ReplSet` (PRIMARY)

### Shard 2 (standalone replica set)
- `shard2-1:27018` — единственный узел `shard2ReplSet` (PRIMARY)

### Router (mongos)
- `mongos:27017` — Маршрутизатор клиентских запросов

**Итого:** 6 узлов MongoDB (3 config servers + 2 shard nodes + 1 mongos).

## Требования

- Docker и Docker Compose (или совместимый Podman)
- Рекомендуется ≥4 CPU и ≥8 GB RAM
- Bash для запуска вспомогательных скриптов

## Запуск стенда

### 1. Автоматическая настройка (рекомендуется)

```bash
make verify KEEP=1
```

Команда запускает полный сценарий `verify`: поднимает инфраструктуру, выполняет bootstrap replica set, при необходимости загружает демо-данные и проводит проверки. Детали перечислены в разделе «Полная автоматическая проверка». При `KEEP=1` окружение остаётся запущенным.

### 2. Ручная настройка (пошаговая)

#### Шаг 1. Запуск контейнеров

```bash
# Запустить config servers и shards
make up-core

# Запустить mongos
make up-router
```

#### Шаг 2. Инициализация replica set

```bash
# Config servers
docker exec -it configSrv-1 mongosh --port 27019 --eval "
rs.initiate({
  _id: 'configReplSet',
  configsvr: true,
  members: [
    { _id: 0, host: 'configSrv-1:27019' },
    { _id: 1, host: 'configSrv-2:27019' },
    { _id: 2, host: 'configSrv-3:27019' }
  ]
});
"

# Shard 1 (один узел)
docker exec -it shard1-1 mongosh --port 27018 --eval "
rs.initiate({
  _id: 'shard1ReplSet',
  members: [
    { _id: 0, host: 'shard1-1:27018' }
  ]
});
"

# Shard 2 (один узел)
docker exec -it shard2-1 mongosh --port 27018 --eval "
rs.initiate({
  _id: 'shard2ReplSet',
  members: [
    { _id: 0, host: 'shard2-1:27018' }
  ]
});
"
```

#### Шаг 3. Регистрация шардов и шардирование коллекции

```bash
docker exec -it mongos mongosh --quiet --eval "
  sh.addShard('shard1ReplSet/shard1-1:27018');
  sh.addShard('shard2ReplSet/shard2-1:27018');
  sh.enableSharding('somedb');
  sh.shardCollection('somedb.helloDoc', { _id: 'hashed' });
"
```

#### Шаг 4. Загрузка демо-данных

```bash
make demo
```

Скрипт создаёт коллекцию `somedb.helloDoc` с несколькими тысячами документов, распределённых по шардам.

## Проверка работы

### Статус replica set

```bash
# Config servers
docker exec -it configSrv-1 mongosh --port 27019 --eval "rs.status()"

# Шарды (каждый состоит из одного узла, статус PRIMARY)
docker exec -it shard1-1 mongosh --port 27018 --eval "rs.status()"
docker exec -it shard2-1 mongosh --port 27018 --eval "rs.status()"
```

### Список шардов

```bash
docker exec -it mongos mongosh --quiet --eval "
  db.getSiblingDB('admin').runCommand({ listShards: 1 }).shards.forEach(
    s => print(s._id + ': ' + s.host)
  );
"
```

### Распределение данных

```bash
docker exec -it mongos mongosh --quiet --eval "
  db.getSiblingDB('somedb').helloDoc.getShardDistribution();
"
```

### Количество документов

```bash
docker exec -it mongos mongosh --quiet --eval "
  print(
    'Total documents:',
    db.getSiblingDB('somedb').helloDoc.countDocuments({})
  );
"
```

### Полная автоматическая проверка

```bash
make verify KEEP=1
```

Скрипт выполняет:
- ✓ Запуск инфраструктуры и bootstrap replica set
- ✓ Проверку списка шардов и статуса балансировщика
- ✓ Контроль, что коллекция `somedb.helloDoc` зашардирована
- ✓ Подсчёт общего количества документов
- ✓ Анализ распределения чанков/документов (скошенность ≤ 60%)
- ✓ Проверку маршрутизации запросов по `_id` (targeted queries)
- ✓ (Опционально) Завершение работы кластера, если `KEEP=0`

## Управление стендом

- Логи `mongos`: `make logs`
- Статус контейнеров: `make ps`
- Остановка кластера: `make down`
- Полный сброс (контейнеры + volumes): `make reset`

## Настройка переменных

```bash
# Количество документов для демо
make verify DOCS=10000 KEEP=1

# Размер батча для вставки
make verify BATCH=500 KEEP=1

# Verbose-режим
make verify VERBOSE=1 KEEP=1

# Имя базы данных и коллекции
make verify DB_NAME=testdb COLL_NAME=testcoll KEEP=1
```

Эти переменные также работают с `make demo`, `make init` и другими целями, если они проксируются скриптами.

## Troubleshooting

### Replica set не инициализируется

- Дождитесь старта контейнеров (30–60 секунд) и повторите команду `make init`.
- Проверьте, что все сервисы в состоянии `Up`: `docker ps`.

### Недостаточно памяти

- Увеличьте объём памяти, доступный Docker, минимум до 8 GB.

### Шарды не добавляются в mongos

- Убедитесь, что у `shard1ReplSet` и `shard2ReplSet` есть PRIMARY (команда `rs.status()`).
- Перезапустите `make init`, чтобы повторить добавление шардов и шардирование коллекции.

### Балансировщик не активен

- Выполните `docker exec -it mongos mongosh --eval "sh.getBalancerState()"`.
- При необходимости включите балансировщик: `docker exec -it mongos mongosh --eval "sh.setBalancerState(true)"`.

## Архитектурные особенности

- **Горизонтальное масштабирование.** Хэш-шардирование по `_id` обеспечивает равномерное распределение документов между шардами и позволяет масштабировать объёмы данных, добавляя новые шарды.
- **Изоляция нагрузок.** Даже с одним узлом в шарде можно моделировать независимые ресурсы, показывая преимущества targeted queries.
- **Простота.** Отсутствие репликации на уровне шардов сокращает время развёртывания и облегчает эксперименты с шардированием.

## Полезные материалы

- [MongoDB Sharding Documentation](https://www.mongodb.com/docs/manual/sharding/)
- [MongoDB Replica Set Concepts](https://www.mongodb.com/docs/manual/replication/)
- [MongoDB Production Checklist](https://www.mongodb.com/docs/manual/administration/production-checklist-operations/)
