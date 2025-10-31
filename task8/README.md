# Задание 8. Выявление и устранение «горячих» шардов

## Общая информация

Требуется:
- Разработать набор метрик, чтобы отслеживать состояние шардов.
- Предложить механизмы автоматического перераспределения данных.

## 1. Метрики мониторинга

C MongoDB можно и нужно собирать как технические метрики (о состоянии кластера), так и прикладные (о распределении данных и запросов).

### Системные метрики (MongoDB-level)

| Метрика	| Источник	| Назначение |
|---|---|---|
|chunks per shard	 | sh.status(), config.chunks |	Определяет, сколько чанков данных хранится на каждом шарде — базовый показатель баланса.|
|chunkSize и диапазоны ключей |	config.chunks	| Позволяет выявить чанки, сосредоточенные в узких диапазонах shard key (hot ranges) |
|ops/sec по шард-серверам	| mongostat, db.serverStatus()|	Общая активность — количество операций чтения/записи |
|network.bytesIn / network.bytesOut	| db.serverStatus()	| Отслеживает сетевую нагрузку между шардом и mongos |
|locks.timeLockedMicros	| db.serverStatus()	| Показывает блокировки на уровне базы/коллекции |

### Прикладные метрики
| Метрика	| Источник	| Назначение |
|---|---|---|
|Количество запросов по категории (category) | Логирование запросов на уровне приложения или MongoDB profiler | Помогает понять, какие категории создают "hot spots" |
|Количество операций на один geo_zone	| Анализ orders.geo_zone |	Выявляет, если шард распределён по географическому признаку, где перегрузка |
|Средняя/максимальная латентность запросов по шард-серверам	| APM (например, MongoDB Atlas Performance Advisor или Prometheus + Grafana) | Позволяет находить узлы с высокой задержкой |
|Размер коллекции и чанков по shard key |	db.collection.stats() и config.chunks.aggregate() |	Анализ распределения данных по диапазонам ключа |

---

## 2. Выявление «горячих» шардов

### Общий план

| Цель |	Инструмент |	Действие |
| --- | --- | --- |
| Мониторинг нагрузки	| Prometheus + mongostat/db.serverStatus() |	Собираем ops/sec, latency, chunk count|
| Анализ дисбаланса |	config.chunks и профайлер |	Ищем hot keys|
| Реакция на дисбаланс	| sh.startBalancer() или reshardCollection()	| Перераспределяем чанки|
| Профилактика	| Hashed / Compound shard keys, zone sharding |	Избегаем горячих зон|
| Кэширование	| Redis / CDN / Application caching	|Снижаем нагрузку на горячие категории|

### Механизмы выявления проблем

#### 1. Анализ распределения чанков

Проверить, сколько чанков у каждого шарда:
```javascript
db.getSiblingDB("config").chunks.aggregate([
  { $group: { _id: "$shard", count: { $sum: 1 } } },
  { $sort: { count: -1 } }
])
```

#### 2. Анализ диапазонов ключей

Проверить, нет ли слишком узких диапазонов category или geo_zone:
```javascript
db.getSiblingDB("config").chunks.aggregate([
  { $group: { _id: "$min.category", chunks: { $sum: 1 } } },
  { $sort: { chunks: -1 } }
])
```

#### 3. Сбор запросов по категориям

Если приложение логирует запросы, можно агрегировать по `product.category` и считать частоту.

#### 4. Использовать профайлер

```javascript
db.setProfilingLevel(1, { slowms: 50 })
db.system.profile.aggregate([
  { $group: { _id: "$ns", avgMillis: { $avg: "$millis" }, count: { $sum: 1 } } },
  { $sort: { avgMillis: -1 } }
])
```

### Механизмы автоматического перераспределения

#### Шардирование по комбинированному ключу

Чтобы избежать "горячих ключей", можно использовать `compound shard key`. Это уменьшает вероятность, что одна категория окажется полностью на одном шарде.

```javascript
sh.shardCollection("orders", { category: 1, _id: 1 })
sh.shardCollection("products", { category: 1, geo_zone: 1 })
```

#### Adaptive Rebalancing (динамическое перераспределение)

MongoDB Balancer уже умеет перемещать чанки, но стоит включить `AutoSplit` и `Balancer window` с контролем по метрикам нагрузки. Если один шард систематически перегружен, можно:
- включить `zone sharding` (т.е. назначить зоны по гео-зоне или категории);
- применить `hashed sharding` для категорий.

Пример  (равномерно распределит категории, даже если “Электроника” чаще запрашивается):
```javascript
sh.shardCollection("products", { category: "hashed" })
```

#### Автоматическое реагирование (через мониторинг)

Можно реализовать систему, где Prometheus + Grafana собирают метрики и запускают скрипт/алерт, если:

- нагрузка (ops/sec) > X% среднего по кластеру;
- latency > 95-й перцентиль;
- количество чанков > порога;

тогда триггерит процесс resharding или rebalancing:
```javascript
mongosh --eval "sh.startBalancer()"
```

или запускает reshardCollection (в MongoDB 5.0+):
```javascript
sh.reshardCollection("products", { newShardKey: { category: "hashed" } })
```

---