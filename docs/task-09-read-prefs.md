# Задание 9: Read Preference и консистентность

**Версия:** 1.0 (final)  
**Дата:** 12.10.2025  
**Проект:** Онлайн-магазин «Мобильный мир»

---

## Цель и охват
Определить, какие **чтения** по коллекциям `products`, `orders`, `carts` выполняются с **primary** и какие допускают **secondary**; задать **допустимую задержку репликации** (max lag) и **обоснование** выбора с учётом частоты обновлений и бизнес‑рисков.

---

## Короткие правила
1) **Критично к свежести (overselling / RYW / транзакции)** → **primary** только.  
2) **Обзорные/каталожные чтения** с редкими апдейтами → **secondary / secondaryPreferred**.  
3) Если нужен upper‑bound на устаревание → **secondary + `maxStalenessSeconds`**.  
4) **Read‑your‑writes** (тот же пользователь сразу после изменения): **primary** или транзакция с `readConcern: "majority"` в одной сессии.  
5) **Writes** всегда идут на **primary**; read preference на них не влияет.

---

## Таблица решений (операции чтения)

| Коллекция | Операция | Read Preference | Max Lag | Частота чтений | Обоснование |
|---|---|---|---|---:|---|
| **products** | Product page (name/price/attrs) | `secondaryPreferred` | ≤ **5 мин** | 2000 QPS | Редкие изменения, stale не критично; финальная цена проверяется позже |
| **products** | Category search / каталог | `secondary` | ≤ **10 мин** | 500 QPS | Browsing; можно кэшировать |
| **products** | **Inventory check** | **`primary`** | **0 ms** | 1000 QPS | **Нельзя overselling**; остатки меняются часто |
| **orders** | Order history (user) | `secondaryPreferred` | ≤ **2 сек** | 200 QPS | Не real‑time, допустим краткий lag |
| **orders** | Order status (детальная карточка) | `primaryPreferred` *(или `secondary`+`maxStalenessSeconds:2`)* | ≤ **2 сек** | 1000 QPS | Важен баланс свежести/нагрузки |
| **carts** | **Get active cart** | **`primary`** | **0 ms** | 2000 QPS | **Same‑session consistency**: пользователь должен видеть свои изменения |
| **carts** | Merge carts (при логине) | **`primary`** | **0 ms** | 50 QPS | Атомарность/потеря товаров недопустимы |

> Примечание: **все записи (writes) — только primary**, с подходящим `writeConcern` (inventory/merge — обычно `majority`, корзина — допустим `w:1`).

---

## Допустимая задержка репликации (ориентиры)
- **Критично свежие данные:** 0 ms (только primary) — *inventory*, *активная корзина*, *транзакции*.  
- **Почти real‑time:** ≤ 2 сек — *order status*, *order history*.  
- **Каталог/поиск:** ≤ 5–10 мин — *product page*, *category search* (при наличии проверки цены на checkout).

---

## Обоснование по коллекциям

### Products
- **Product page / Category search:** обновляются нечасто → можно secondary; экономит primary CPU/IO. На checkout цена и доступность перепроверяются на **primary**.  
- **Inventory check:** частые апдейты; stale ведёт к **overselling** → только **primary**, при необходимости `readConcern: "majority"`.

### Orders
- **History:** события неизменяемые, небольшой lag приемлем → **secondaryPreferred** (или `secondary` с `maxStalenessSeconds:2`).  
- **Status:** меняется раз в часы, но UX чувствителен → **primaryPreferred**; при высокой нагрузке допустим secondary с `maxStalenessSeconds:2` (строго ограничивает устаревание).

### Carts
- **Active cart / Merge:** требуется **read‑your‑writes** и целостность в сессии → **primary**; для merge — транзакция (`readConcern: "majority"`, `writeConcern: "majority"`).

---

## Мини‑примеры (Mongo Shell / драйверы)

**Mongo Shell / mongosh**
```javascript
// Каталог (secondary)
db.products.find({ category: "smartphones" }).readPref("secondary");

// История заказов (secondaryPreferred)
db.orders.find({ user_id: "USR-123" }).readPref("secondaryPreferred");

// Статус заказа (строго ограничить устаревание)
db.orders.findOne({ order_id: "ORD-2025-123" })
  .readPref("secondary", { maxStalenessSeconds: 2 });

// Остатки / корзина / merge — только primary
db.products.findOne({ product_id: "PROD-1" }, { inventory: 1 }).readPref("primary");
db.carts.findOne({ session_id: "SESS-abc", status: "active" }).readPref("primary");
```

**PyMongo (пример ограничения устаревания)**
```python
from pymongo import ReadPreference
db.orders.find_one(
    {"order_id": "ORD-2025-123"},
    read_preference=ReadPreference.SECONDARY,
    max_staleness_seconds=2
)
```

---

## Как контролировать replication lag (минимум)
```javascript
// На secondary: сводка отставания
rs.printSecondaryReplicationInfo()

// Через serverStatus (на узле)
db.serverStatus().metrics.repl.apply // события применения oplog
// (ориентируйтесь на rs.printSecondaryReplicationInfo как на быстрый чек)
```


---

## Ожидаемый эффект (оценка)

Базовый профиль чтений (из таблицы): product page **2000 QPS**, catalog **500**, order status **1000**, order history **200**, inventory **1000**, active cart **2000** → всего ~**6700 QPS** на primary (до оптимизации).  
После применения read preference:
- Уход на вторичные: product page **2000**, catalog **500**, order history **200** → **2700 QPS** offload (~**40.3%** от 6700).  
- Если **50%** чтений статуса заказов (1000 QPS) уйдут на secondary с `maxStalenessSeconds:2` → ещё **≈500 QPS** offload, суммарно **≈3200/6700 ≈ 47.8%**.

Практически: снижение CPU/IO на primary на **40–48%** для чтений; высвобождение ресурса под записи/транзакции.


---

## Риски и митигации (кратко)
- **Stale цена в каталоге** → финальная проверка на checkout (primary).  
- **Stale статус заказа** → `primaryPreferred` или `maxStalenessSeconds:2`.  
- **Высокий lag** → алёрт и временный перевод чтений на `primary` для затронутых операций.  
- **Рост нагрузки на primary** → кэширование каталога (TTL 3–5 мин), индексы под реальную выборку, масштабирование шардов.

---

**Статус:** Готово к сдаче
