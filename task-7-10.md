
# Архитектурный документ: задания 7–10

## Задание 7. Проектирование схем коллекций для шардирования данных

### Коллекция `orders`
```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "created_at": ISODate,
  "items": [
    { "product_id": ObjectId, "price": Decimal128, "quantity": Int32 }
  ],
  "status": "new|paid|shipped|delivered|cancelled",
  "total": Decimal128,
  "geo_zone": "MSK|SPB|EKAT|..."
}
```

**Кандидаты на шард-ключ:**
- `{ user_id: 1 }` — хорошо для поиска истории заказов конкретного клиента.
- `{ geo_zone: 1, _id: "hashed" }` — вариант для распределения нагрузки по регионам + равномерность.

**Выбор:**  
```js
sh.shardCollection("somedb.orders", { user_id: "hashed" })
```

---

### Коллекция `products`
```json
{
  "_id": ObjectId,
  "name": String,
  "category": String,
  "price": Decimal128,
  "stock": { "MSK": Int32, "SPB": Int32, "EKAT": Int32 },
  "attributes": { "color": String, "size": String }
}
```

**Кандидаты на шард-ключ:**
- `{ category: 1 }` — может привести к «горячему» шарду.
- `{ _id: "hashed" }` — равномерное распределение.
- `{ category: 1, _id: "hashed" }` — маршрутизация по категории + равномерность внутри.

**Выбор:**  
```js
sh.shardCollection("somedb.products", { category: 1, _id: "hashed" })
```

---

### Коллекция `carts`
```json
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "session_id": String,
  "items": [
    { "product_id": ObjectId, "quantity": Int32 }
  ],
  "status": "active|ordered|abandoned",
  "created_at": ISODate,
  "updated_at": ISODate,
  "expires_at": ISODate
}
```

**Выбор:**  
```js
sh.shardCollection("somedb.carts", { session_id: "hashed" })
```

---

## Задание 8. Устранение «горячих» шардов

### Метрики мониторинга
- Docs per shard (`db.collection.getShardDistribution()`).
- Chunk imbalance (`sh.status()`, balancer logs).
- Replication lag.
- Query targeting (профайлер MongoDB).
- Category hit ratio.

### Механизмы устранения
- **Balancer** — автоматическая миграция чанков.
- **Zone sharding** — распределение категорий по нескольким шардам.
- **Split chunks** — ручное деление больших чанков:
```js
sh.splitAt("somedb.products", { category: "Electronics", _id: MinKey })
```

---

## Задание 9. Чтение с реплик и консистентность

| Коллекция  | Операция                                         | Replica Pref.          | Допустимая задержка |
|------------|--------------------------------------------------|------------------------|----------------------|
| **orders** | Создание заказа / обновление статуса            | primary                | 0                    |
|            | Просмотр истории заказов                        | secondaryPreferred     | ≤ 5 сек              |
| **products** | Обновление остатков при покупке                 | primary                | 0                    |
|            | Поиск товаров по категориям / фильтрация        | secondaryPreferred     | ≤ 2–3 сек            |
|            | Отображение описания товара                      | secondaryPreferred     | ≤ 10 сек             |
| **carts**  | Добавление товара / объединение корзин          | primary                | 0                    |
|            | Получение текущей корзины (active)               | primary                | 0                    |
|            | Получение истории старых корзин                 | secondaryPreferred     | ≤ 5 сек              |

---

## Задание 10. Миграция на Cassandra

### 10.1 Какие данные переносить
- **В Cassandra**: orders (история), carts (сессии).
- **В MongoDB**: products (гибкая структура и фильтры).

### 10.2 Модель Cassandra

**Orders**
```sql
CREATE TABLE orders (
  user_id UUID,
  order_id TIMEUUID,
  created_at TIMESTAMP,
  status TEXT,
  total DECIMAL,
  geo_zone TEXT,
  items LIST<FROZEN<MAP<TEXT, DECIMAL>>>,
  PRIMARY KEY ((user_id), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

**Carts**
```sql
CREATE TABLE carts (
  session_id UUID,
  updated_at TIMESTAMP,
  user_id UUID,
  status TEXT,
  items LIST<FROZEN<MAP<TEXT, INT>>>,
  expires_at TIMESTAMP,
  PRIMARY KEY ((session_id), updated_at)
);
```

### 10.3 Стратегии консистентности
- **Hinted Handoff** — carts (быстрая eventual consistency).
- **Read Repair** — orders (важна точность истории).
- **Anti-Entropy Repair** — периодическая синхронизация.


