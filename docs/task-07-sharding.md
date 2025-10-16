# Задание 7: Проектирование схем коллекций для шардирования данных

**Версия:** 2.2 (final)  
**Дата:** 12.10.2025  
**Проект:** Онлайн-магазин «Мобильный мир»

---

## Сводка решений

| Коллекция | Шард-ключ | Тип | Целевая операция | SG %* |
|---|---|---|---|---|
| Products | {category: 1, product_id: 1} | Compound | Каталог по категории, обновление остатков | ≈ 8.3 |
| Orders   | {user_id: "hashed"}          | Hashed   | История и статус по (user_id, order_id)   | ≈ 2.8 |
| Carts    | {session_id: "hashed"}       | Hashed   | Все CRUD по сессии                        | ≈ 0.0 |

\* Методика: SG % = SG_ops / (Targeted_ops + SG_ops). Допущения нагрузки: Products 500 (каталог) + 50 (карточка) + 50 (обновления); Orders 200 (история) + 150 (статус) + 10 (геосрезы); Carts — все по session_id.

---

## Правила

1. Глобальный идентификатор: `_id` равен естественному ключу (product_id / order_id / session_id).  
2. Статус заказа: запрос по `(user_id, order_id)` для targeted-доступа.  
3. Карточка товара: запрос по `(category, product_id)` для targeted-доступа.  
4. Индексы — только под подтверждённые паттерны запросов.
5. Генерация `_id`: Products — `product_id` (из PIM/каталога); Orders — UUIDv7; Carts — случайный 128-бит `session_id`.


---

## Products

### Схема
```javascript
{
  _id: "PROD-12345",
  product_id: "PROD-12345",
  category: "Электроника",
  name: "iPhone 15 Pro",
  price: 89990.00,
  stock: [
    { geozone: "Москва", quantity: 150, reserved: 12 },
    { geozone: "СПб",    quantity: 80,  reserved: 5 }
  ],
  attributes: { brand: "Apple", model: "15 Pro" },
  created_at: ISODate("2024-09-01"),
  updated_at: ISODate("2025-01-15")
}
```

### Выбор и альтернатива (кратко)
- Выбор `{category, product_id}`: локализует каталожные запросы и обновления остатков.
- Альтернатива `{product_id: "hashed"}` делает каталожные запросы SG на всех шардах → избыточные затраты.
- Итог: основная нагрузка (каталог) targeted; редкие запросы только по product_id допустимы как SG.

### Индексы
- `{category: 1, product_id: 1}`  
- `{category: 1, price: 1}`

### Команды MongoDB
```javascript
sh.enableSharding("mobile_world")
sh.shardCollection("mobile_world.products", { category: 1, product_id: 1 })
db.products.createIndex({ category: 1, price: 1 })
```

### Примечание по SG
- raw: ≈ **8.3%** (50 SG из 600 операций).
- weighted (альтернатива `{product_id: "hashed"}`, 4 шарда): ≈ **78%** SG на каталожных запросах.

### Паттерны запросов (примеры)
```javascript
// Каталог (targeted)
db.products.find({ category: "Электроника", price: { $gte: 50000, $lte: 100000 } })

// Карточка товара (targeted, при передаче category)
db.products.findOne({ category: "Электроника", product_id: "PROD-12345" })
```

---

## Orders

### Схема
```javascript
{
  _id: "ORD-2025-123456",
  order_id: "ORD-2025-123456",
  user_id: "USER-98765",
  order_date: ISODate("2025-01-15"),
  items: [
    { product_id: "PROD-12345", category: "Электроника", quantity: 1, price: 89990.00 }
  ],
  status: "processing",
  total_amount: 135970.00,
  geozone: "Москва",
  shipping_address: { city: "Москва", street: "Тверская, 1" },
  created_at: ISODate("2025-01-15"),
  updated_at: ISODate("2025-01-15")
}
```

### Выбор и альтернатива (кратко)
- Выбор `{user_id: "hashed"}`: история и статус по `(user_id, order_id)` — targeted; равномерное распределение.
- Альтернатива `{geozone, user_id}`: неравномерность трафика по регионам и усложнение user-операций; требований data-residency нет.
- Итог: geozone остаётся атрибутом; при появлении требований возможен resharding на `{geozone, user_id}`.

### Индексы
- `{user_id: 1, order_date: -1}`  
- `{user_id: 1, order_id: 1}`  
- `{status: 1, order_date: -1}`  
- `{geozone: 1, order_date: -1}`

### Команды MongoDB
```javascript
sh.shardCollection("mobile_world.orders", { user_id: "hashed" })
db.orders.createIndex({ user_id: 1, order_date: -1 })
db.orders.createIndex({ user_id: 1, order_id: 1 })
db.orders.createIndex({ status: 1, order_date: -1 })
db.orders.createIndex({ geozone: 1, order_date: -1 })
```

### Примечание по SG
- raw: ≈ **2.8%** (редкие запросы по geozone).
- weighted: ≈ **12.1%** при учёте мультишард-оверхода.

### Паттерны запросов (примеры)
```javascript
// История пользователя (targeted)
db.orders.find({ user_id: "USER-98765" }).sort({ order_date: -1 })

// Статус заказа (targeted)
db.orders.findOne({ user_id: "USER-98765", order_id: "ORD-2025-123456" })
```

---

## Carts

### Схема
```javascript
{
  _id: "SESS-abc123",
  session_id: "SESS-abc123",
  user_id: "USER-98765",
  items: [
    { product_id: "PROD-12345", category: "Электроника", quantity: 1, price: 89990.00 }
  ],
  total_amount: 89990.00,
  status: "active",
  created_at: ISODate("2025-01-15"),
  updated_at: ISODate("2025-01-15")
}
```

### Выбор и альтернатива (кратко)
- Выбор `{session_id: "hashed"}`: единый ключ для гостей и пользователей; отсутствие hot-spot на `user_id = null`.
- Альтернатива `{user_id: "hashed"}` неприменима из-за доли гостевого трафика.

### Индексы
- `{user_id: 1, status: 1}`  
- `{updated_at: 1}` с `expireAfterSeconds: 2592000`

### Команды MongoDB
```javascript
sh.shardCollection("mobile_world.carts", { session_id: "hashed" })
db.carts.createIndex({ user_id: 1, status: 1 })
db.carts.createIndex({ updated_at: 1 }, { expireAfterSeconds: 2592000 })
```

### Паттерны запросов (пример)
```javascript
// Получение корзины по сессии (targeted)
db.carts.findOne({ session_id: "SESS-abc123" })
```

---

## Покрытие требований

- Products: каталог по категории и обновления остатков — targeted; карточка товара — targeted по `(category, product_id)`.  
- Orders: история по пользователю и статус заказа — targeted; геосрезы допустимы как редкий SG.  
- Carts: все операции по `session_id` — targeted; очистка неактивных корзин через TTL.

---


## Границы и SLO

**Boundary conditions (операционный масштаб):**
- Products: ≤ 10M документов
- Orders: ≤ 1M заказов/сутки; OLTP-горизонт хранения ≤ 365 дней
- Carts: ≤ 500K активных корзин
- Кластер: 4–8 шардов; 3 реплики/шард

**Latency SLO (p95, OLTP):**
- Products (targeted каталог): < 15 ms
- Products (редкий SG): < 40 ms
- Orders (user_id targeted): < 12 ms
- Carts (session_id targeted): < 10 ms

## Триггеры пересмотра

- Multi-region / data residency → рассмотреть `{geozone: 1, user_id: "hashed"}` для Orders.  
- Перекос категорий >50% → tag-aware sharding для Products.  
- Рост доли SG сверх SLA → кэш каталога / материализованные представления.
