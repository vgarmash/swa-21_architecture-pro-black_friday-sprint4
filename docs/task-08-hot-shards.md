# Задание 8: Выявление и устранение «горячих» шардов

**Версия:** 2.0 (final)  
**Дата:** 12.10.2025  
**Проект:** Онлайн-магазин «Мобильный мир»

---

## Контекст задания
Перегрузка одного из шардов из‑за категории «Электроника»; требуется архитектурный документ с метриками мониторинга, механизмами устранения дисбаланса и примерами команд/настроек MongoDB. fileciteturn4file0

---

## Сводка (минимально‑достаточно)

| Цель | Что делаем | Порог | Автодействие |
|---|---|---|---|
| Найти hot shard | Следим за CPU/QPS дисбалансом | CPU > 85% (5m), QPS imbalance > 50% | Alert + агрессивный balancer |
| Увидеть дисбаланс данных | Проверяем chunks/документы | Chunks > 50% CRIT; Jumbo=true | split/move + balancer |
| Снизить горячие чтения | Read scaling + кэш топ‑товаров | p95 > SLO | secondaryPreferred*, Redis TTL |
| Срочно разгрузить | Точечный moveChunk | CRITICAL инцидент | Перенос горячих диапазонов |
| Профилактика | Корректный shard key/индексы | Targeted ≥ 70% | (см. Задание 7) |

\* Только для допустимых eventual‑consistency запросов.

---

## Границы и SLO

**Boundary:** Products ≤ 10M; Orders ≤ 1M/сутки; Carts ≤ 500K активных; 4–8 шардов, 3 реплики/шард.  
**Latency SLO (p95):** Каталог < 15 ms; История < 12 ms; Carts < 10 ms.  
**Resource SLO:** CPU < 70% sustained / < 85% peak; RAM resident < 80%; Disk await < 10 ms.

---

## SG‑методика и проверка

- **Raw SG:** доля запросов, где `winningPlan.shards.length > 1` (онлайн‑контроль).  
- **Weighted SG:** raw × число шардов (для capacity‑анализа).

```javascript
// Быстрая проба SG (на mongos)
function sgRate(ns, filter, n=30){let s=0,g=0;for(let i=0;i<n;i++){const e=db.getCollection(ns).find(filter).explain("queryPlanner");const k=e?.queryPlanner?.winningPlan?.shards?.length||1;k>1?s++:g++;}return{scatter:s,targeted:g,sg_pct:(s/(s+g)*100).toFixed(1)};}
```

---

## Метрики (что → пороги → как проверить)

### 1) Ресурсы узла
- **CPU** — Warn > 70%, Crit > 85%.  
  ```bash
  mpstat 1 5 | awk '/all/ {print 100-$12"% CPU"}'; mongostat --host <shard:port> -n 3 1
  ```
- **Память / WT cache hit** — Warn: RAM > 80%, Cache hit < 90%.  
  ```javascript
  s=db.serverStatus(); print("residentMB=",s.mem.resident);
  c=s.wiredTiger.cache; print("cache_hit=",((c["pages requested from the cache"]-c["pages read into cache"])/c["pages requested from the cache"]*100).toFixed(1),"%");
  ```
- **Disk I/O (await)** — Warn > 10 ms, Crit > 50 ms.  
  ```bash
  iostat -x 1 3 | awk '/nvme|sd/ {print $1,$10"ms await"}'
  ```
- **Network** — следим за bytesIn/bytesOut, drops.  
  ```javascript
  n=db.serverStatus().network; print("in=",n.bytesIn," out=",n.bytesOut)
  ```

### 2) Распределение нагрузки
- **QPS per shard** — raw imbalance = `(max-min)/avg×100`; Warn > 30%, Crit > 50%.  
  ```javascript
  b=db.serverStatus().opcounters.query; sleep(1000); a=db.serverStatus().opcounters.query; print("QPS=",a-b)
  ```
- **Data/Docs per shard** — объёмный дисбаланс.  
  ```javascript
  db.products.getShardDistribution()
  ```
- **Chunks per shard / Jumbo** — управляемость перемещений.  
  ```javascript
  db.getSiblingDB("config").chunks.aggregate([
    { $match:{ ns:"mobile_world.products"} },
    { $group:{ _id:"$shard", chunks:{ $sum:1 }} },
    { $sort:{ chunks:-1 }}
  ])
  db.getSiblingDB("config").chunks.find({ ns:"mobile_world.products", jumbo:true })
  ```

### 3) Уровень приложения
- **Latency p95/p99** — Warn p95 > 100 ms; Crit p95 > 300 ms.  
  ```javascript
  // включать кратко, отключать после анализа
  db.setProfilingLevel(1,{slowms:100});
  db.system.profile.find({ ns:"mobile_world.products", millis:{ $gt:100 }}).sort({ millis:-1 }).limit(10);
  db.setProfilingLevel(0);
  ```
- **Scatter‑gather rate** — см. `sgRate(...)` выше.

---

## Обнаружение и реакция

**Триггеры (любой):** CPU > 85% (5m) • QPS imbalance > 50% • p95 > SLO.  
**Реакция:** Alert → агрессивный balancer → диагностика (QPS/Chunks/Slow).

---

## Механизмы (коротко и корректно)

**A. Balancer** — автоматическое выравнивание; при инциденте — агрессивный режим.  
```javascript
sh.startBalancer();
db.getSiblingDB("config").settings.updateOne(
  { _id:"balancer" },
  { $set:{ _secondaryThrottle:false, _waitForDelete:false } },
  { upsert:true }
)
```

**B. Chunk split** — авто по размеру; вручную для hot‑chunks.  
- Для **hashed**: split/границы — по **хеш‑значениям** из `config.chunks`.  
- Для **range**: по исходным полям.  
```javascript
// Пример (range‑key): split отбором
sh.splitFind("mobile_world.products", { category:"Электроника" })
```

**C. MoveChunk (emergency)** — онлайн; возможны краткие блокировки на commit.  
```javascript
sh.moveChunk("mobile_world.products", { category:"Электроника", product_id:"PROD-12345" }, "shard2RS")
```

**D. Zone sharding** — только для **range‑keys**; сначала refine до range‑совместимого префикса.  
```javascript
db.adminCommand({ refineCollectionShardKey:"mobile_world.products", key:{ category:1, product_id:1 }})
sh.addTagRange("mobile_world.products",
  { category:"Электроника", product_id:MinKey },
  { category:"Электроника", product_id:MaxKey },
  "high-performance"
)
```

**E. Read scaling & Cache** — `secondaryPreferred` для допустимых чтений; Redis кэш топ‑товаров (TTL≈300s).

---

## Плейбук (15 минут)

1) Включить balancer, установить агрессивные флаги.  
2) Каталог — `secondaryPreferred`; прогреть/включить кэш для топ‑товаров.  
3) Точечные `moveChunk` «горячих» диапазонов до нормализации метрик.

---

## Кейс «Электроника» (сжато)

- shard1 QPS ≈ **19k**, shard2 ≈ **1k** → raw‑imbalance **180%**, p95 каталога > **300 ms**, CPU shard1 > **90%**.  
- Причина: 3 «celebrity» товара (10k/5k/3k QPS) пришлись на один шард при hashed‑распределении документов.  
- Митиг.: шаги плейбука.  
- План 1–2 недели: `refineCollectionShardKey` → `{ category:1, product_id:1 }` (или полный reshard); при необходимости — зоны (range‑key).

---

**Статус:** Готово к сдаче
