# MongoDB Sharding + Replication + Redis Cache

Стенд `sharding-repl-cache` основан на `../mongo-sharding-repl` и добавляет уровень кеширования для API. Базовые инструкции по управлению шардированным кластером и replica set остаются теми же, что и в `../mongo-sharding/README.md`. Здесь описаны дополнительные компоненты, связанные с Redis и FastAPI.

## Архитектура

- **Config Server Replica Set**: `configSrv-1/2/3` (порт 27019).
- **Shard 1 Replica Set**: `shard1-1/2/3` (порт 27018).
- **Shard 2 Replica Set**: `shard2-1/2/3` (порт 27018).
- **Router**: `mongos` (порт 27017) — единая точка входа в кластер.
- **Redis**: `redis` — кеш запросов пользователей.
- **API**: `pymongo_api` — FastAPI-приложение c включённым кешем (`/docs` на порту 8080).

**Итого:** 12 контейнеров (MongoDB-инфраструктура + Redis + API).

## Быстрый старт

```bash
make verify KEEP=1
```

Команда поднимает полный стенд (MongoDB, mongos, Redis, API), инициализирует replica set, добавляет шарды, создаёт демо-данные, проверяет распределение документов и валидирует API:
- подсчёт документов и распределение по шардам;
- наличие реплик (по три на каждый шард);
- успешная работа Redis-кеша (`/<collection>/users` вторым запросом быстрее 100 мс);
- отчёт API о подключении через `mongos`, количестве документов и реплик.

После выполнения сценария инфраструктура остаётся запущенной при `KEEP=1`.

## Ручной запуск

1. **Поднять инфраструктуру**:
   ```bash
   make up-all
   ```
   Стартуют MongoDB узлы, `mongos`, Redis и API.
2. **Инициализация replica set и шардов** (если не использовалась `make verify`):
   ```bash
   make init
   ```
3. **Генерация демо-данных** с полями `name`, `age`, `email` для эндпоинта `/users`:
   ```bash
   make demo
   ```

API доступно по адресу `http://localhost:8080`. Корневой эндпоинт (`/`) показывает сводную информацию о коллекциях, шардах и количестве реплик. Эндпоинт `/<collection>/users` кешируется на 60 секунд в Redis.

## Проверка кеширования вручную

```bash
curl -s http://localhost:8080/helloDoc/users >/dev/null   # первый запрос ≈1 сек
curl -s -w '%{time_total}\n' http://localhost:8080/helloDoc/users -o /dev/null
```

Вторая команда должна показать время <0.1 сек. Сбросить кеш можно перезапуском Redis (`docker restart redis`).

## Работа с Redis и API

- Просмотр логов API: `docker logs -f pymongo_api`
- Подключение к Redis: `docker exec -it redis redis-cli`
- Рукописное наполнение кеша не требуется — `fastapi-cache2` делает это автоматически.

## Дополнительно

- Потоки `mongos`: `make logs`
- Статус контейнеров: `make ps`
- Остановка: `make down`
- Полный сброс: `make reset`

Если меняете параметры коллекции (`DB_NAME`, `COLL_NAME`), передавайте их через переменные окружения при вызове `make verify`, `make demo` и `make init` — скрипты проксируют значения внутрь контейнеров и API.
