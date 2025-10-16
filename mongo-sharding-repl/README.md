# MongoDB Sharding с Репликацией

Стенд `mongo-sharding-repl` расширяет базовую конфигурацию `../mongo-sharding`, добавляя репликацию на уровне шардов. Общая последовательность запуска, проверки и обслуживания подробно описана в `../mongo-sharding/README.md`. На этой странице собраны отличия и дополнительные сценарии, характерные только для стенда с репликацией.

## Ключевые отличия от базового стенда

- Каждый шард разворачивается как replica set из трёх узлов, что обеспечивает отказоустойчивость и чтение со вторичных.
- Проверки `make verify` дополнительно убеждаются, что в кластере присутствует 6 шардовых реплик (3 + 3), а распределение данных остаётся сбалансированным.
- Скрипт `make init` инициализирует расширенные конфигурации replica set (по три члена в каждом шарде).
- Рекомендуемые тесты включают автоматическую проверку failover-сценариев для узлов PRIMARY и SECONDARY.

## Архитектура

### Config Server Replica Set (3 узла)
- `configSrv-1:27019` — Config Server 1
- `configSrv-2:27019` — Config Server 2
- `configSrv-3:27019` — Config Server 3

### Shard 1 Replica Set (3 узла)
- `shard1-1:27018` — Shard 1, узел 1 (PRIMARY)
- `shard1-2:27018` — Shard 1, узел 2 (SECONDARY)
- `shard1-3:27018` — Shard 1, узел 3 (SECONDARY)

### Shard 2 Replica Set (3 узла)
- `shard2-1:27018` — Shard 2, узел 1 (PRIMARY)
- `shard2-2:27018` — Shard 2, узел 2 (SECONDARY)
- `shard2-3:27018` — Shard 2, узел 3 (SECONDARY)

### Router (mongos)
- `mongos:27017` — Маршрутизатор для клиентских запросов

**Итого:** 10 узлов MongoDB (3 config servers + 6 shard nodes + 1 mongos).

## Запуск и проверки

- Быстрый старт: `make verify KEEP=1`. Команда запускает все контейнеры, инициализирует replica set для config servers и шардов, добавляет шарды в `mongos`, генерирует ≥1000 документов и делает дополнительные проверки на отказоустойчивость реплик.
- Поэтапный запуск (`make up-core`, `make up-router`, `make init`, `make demo`) идентичен базовому стенду. Подробные инструкции остаются в `../mongo-sharding/README.md`.
- Для ручной инспекции репликации подключайтесь к узлам:
  ```bash
  docker exec -it shard1-1 mongosh --port 27018 --eval "rs.status()"
  docker exec -it shard2-1 mongosh --port 27018 --eval "rs.status()"
  ```
- Проверить список шардов и их хосты можно через `mongos`:
  ```bash
  docker exec -it mongos mongosh --quiet --eval "
    db.getSiblingDB('admin').runCommand({ listShards: 1 }).shards.forEach(
      s => print(s._id + ': ' + s.host)
    );
  "
  ```

## Тестирование отказоустойчивости

### Остановка вторичного узла

```bash
# Остановить вторичный узел в shard1
docker stop shard1-2

# Проверить, что запросы продолжают работать
docker exec -it mongos mongosh --eval "
  db.getSiblingDB('somedb').helloDoc.countDocuments({});
"

# Статус replica set (один узел будет в состоянии DOWN/RECOVERING)
docker exec -it shard1-1 mongosh --port 27018 --eval "rs.status()"

# Восстановить узел
docker start shard1-2
```

### Остановка PRIMARY узла

```bash
# Остановить PRIMARY узел в shard1
docker stop shard1-1

# Подождать ~10–15 секунд для автоматических выборов
sleep 15

# Проверить, что появился новый PRIMARY
docker exec -it shard1-2 mongosh --port 27018 --eval "rs.status()"

# Проверить, что запросы продолжают работать
docker exec -it mongos mongosh --eval "
  db.getSiblingDB('somedb').helloDoc.countDocuments({});
"

# Восстановить узел
docker start shard1-1
```

## Дополнительные команды replica set

```bash
# Добавление нового узла в shard1
docker exec -it shard1-1 mongosh --port 27018 --eval "rs.add('shard1-4:27018')"

# Изменение приоритета узла
docker exec -it shard1-1 mongosh --port 27018 --eval "
  cfg = rs.conf();
  cfg.members[1].priority = 2;
  rs.reconfig(cfg);
"
```

Общие операции (логи, управление контейнерами, сброс окружения, настройки переменных и troubleshooting) описаны в `../mongo-sharding/README.md`. Используйте те же команды и примечания — они полностью применимы к стенду с репликацией.

## Полезные ссылки

- [MongoDB Sharding Documentation](https://www.mongodb.com/docs/manual/sharding/)
- [MongoDB Replication Documentation](https://www.mongodb.com/docs/manual/replication/)
- [MongoDB Production Checklist](https://www.mongodb.com/docs/manual/administration/production-checklist-operations/)
