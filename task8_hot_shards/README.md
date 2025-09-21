# task8_hot_shards

Цель: выявление и устранение «горячих» шардов в кластере MongoDB.

## 1) Метрики (основные SLI) и пороги (примерные)
- **Операции/сек по шарду**: `opcounters` (insert/query/update/delete) на каждом `mongod` (PRIMARY/SECONDARY). Порог: > P95 по кластерам + 30% в течение 5–10 мин.
- **Средняя/макс. латентность операций**: `metrics.queryExecutor.scannedObjects`, `commandLatencyHistogram` на `mongos`. Порог: рост P95 > 2× базовой.
- **CPU/IO/Network** на узлах шардов. Порог: CPU > 80% 5 мин; disk util > 70%; net satur > 70%.
- **Queue / Active connections**: `globalLock.activeClients`, `connections.current`.
- **Chunk distribution**: число чанков на шард, объём данных/шард.
- **Balancer state**: длительность миграций, количество отложенных заданий.
- **Replication lag** (если RS): `rs.printSlaveReplicationInfo()`; порог > 5–10 сек для OLTP.

Алерты (пример):
- shard_X: ops/s > cluster_p95_ops × 1.3 и latency_p95 × 2 в 10 мин → рассматривать как «горячий».

## 2) Выявление «горячих» шардов (команды)
- Краткий статус шардирования:
```javascript
sh.status()
```
- Список шардов и их размеры:
```javascript
db.getSiblingDB('admin').runCommand({ listShards: 1 })
```
- Распределение чанков по шардом:
```javascript
use config
// Кол-во чанков по коллекции
printjson(db.chunks.aggregate([
  { $match: { ns: 'somedb.products' } },
  { $group: { _id: '$shard', chunks: { $sum: 1 } } },
  { $sort: { chunks: -1 } }
]).toArray())
```
- Топ «горячих» ключевых диапазонов (по сплитам/миграциям):
```javascript
printjson(db.chunks.aggregate([
  { $match: { ns: 'somedb.products' } },
  { $group: { _id: '$min.category', cnt: { $sum: 1 } } },
  { $sort: { cnt: -1 } }, { $limit: 10 }
]).toArray())
```
- Нагрузка с `mongos` (latency):
```javascript
// Начиная с 6.0 доступны гистограммы
use admin
printjson(db.serverStatus().opLatencies)
```
- Репликационное отставание:
```javascript
rs.printSlaveReplicationInfo()
```

## 3) Стратегии ремедиации
1. Балансировка чанков
```javascript
sh.setBalancerState(true)
sh.startBalancer()
// при необходимости — ручные миграции
sh.moveChunk('somedb.products', { category: 'Electronics' }, 'rsB')
```
2. Уточнение shard‑ключа (refineKey) для лучшей кардинальности
```javascript
sh.refineCollectionShardKey('somedb.products', { category: 1, _id: 'hashed' })
```
3. Перешардирование коллекции (MongoDB 5.0+ Online Reshard)
```javascript
use admin
sh.reshardCollection('somedb.orders', {
  key: { user_id: 1, created_at: -1 },  // или новый ключ
  unique: false,
  numInitialChunks: 8
})
```
4. Зональная шардизация (геозоны)
```javascript
sh.addShardToZone('rsA', 'MSK')
sh.addShardToZone('rsB', 'SPB')
sh.updateZoneKeyRange('somedb.products', { 'stock_by_zone.geo': 'MSK' }, { 'stock_by_zone.geo': 'MSZ' }, 'MSK')
```
5. Ротация горячих категорий (перемещение диапазонов)
```javascript
sh.moveChunk('somedb.products', { category: 'Electronics' }, 'rsB')
```
6. Кеширование и денормализация
- Включить Redis для самых горячих маршрутов чтения.
- Предвычислять витрины для страницы категории.

7. Ограничение «бурстов» и QoS
- Rate limit на API Gateway для конкретных категорий/юзеров.
- Пул фоновых воркеров для переработки очередей.

## 4) Процедура действий (пошагово)
1) Подтвердить горячий шард по метрикам (ops/s, latency, CPU/IO) и дисбаланс чанков.
2) Включить баланcер, дождаться миграций; при необходимости — `moveChunk` по диапазонам ключей.
3) Если ключ малокардинален — `refineCollectionShardKey`.
4) Если характер нагрузки изменился — `reshardCollection` (онлайн), выбрать ключ с лучшей кардинальностью.
5) Для геозон — задать зоны и переместить диапазоны.
6) Защитить горячие эндпоинты: кеш, rate limit.
7) Контроль: latency вернулась к базовой; распределение чанков выровнялось.

## 5) Быстрые one‑liners (bash)
```bash
# Топ шардов по чанкам для products
mongosh --quiet --eval 'use config; db.chunks.aggregate([{ $match:{ns:"somedb.products" } },{ $group:{ _id:"$shard", c:{ $sum:1 } } },{ $sort:{ c:-1 } }]).toArray()'

# Латентность op на mongos
mongosh --quiet --eval 'db.getSiblingDB("admin").serverStatus().opLatencies'
``` 