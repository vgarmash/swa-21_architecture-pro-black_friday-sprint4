# Архитектурный документ: Шардирование коллекций MongoDB

## Коллекция `carts`

### Схема документа
```javascript
{
  "_id": ObjectId,
  "user_id": ObjectId, // NULLABLE - может быть null для гостей
  "session_id": String, // NULLABLE - может быть null для авторизованных пользователей
  "items": [
    {
      "product_id": ObjectId,
      "quantity": Number
    }
  ],
  "status": String, // "active" | "ordered" | "abandoned"
  "created_at": ISODate,
  "updated_at": ISODate,
  "expires_at": ISODate // Для TTL индекса
}
```

### Стратегия шардирования
**Диапазонное шардирование по составному ключу `{user_id: 1, session_id: 1}`**

```javascript
sh.shardCollection("database.carts", { "user_id": 1, "session_id": 1 })
```

### Обоснование выбора
- **Локализация запросов**: Основные операции поиска активной корзины (`{user_id, status:"active"}` и `{session_id, status:"active"}`) выполняются на одном шарде
- **Эффективное слияние корзин**: Операция объединения гостевой и пользовательской корзин выполняется в рамках одного шарда
- **Равномерное распределение**: Избегает "горячих" точек благодаря уникальной природе `user_id` и `session_id`

### Дополнительные индексы
```javascript
db.carts.createIndex({ "user_id": 1, "session_id": 1, "status": 1 })
db.carts.createIndex({ "expires_at": 1 }, { expireAfterSeconds: 0 })
```

---

## Коллекция `orders`

### Схема документа
```javascript
{
  "_id": ObjectId,
  "customer_id": ObjectId,
  "order_date": ISODate,
  "items": [
    {
      "product_id": ObjectId,
      "name": String,
      "category": String,
      "price": Number,
      "quantity": Number
    }
  ],
  "status": String,
  "total_amount": Number,
  "geo_zone": String
}
```

### Стратегия шардирования
**Хеш-шардирование по ключу `customer_id`**

```javascript
sh.shardCollection("database.orders", { "customer_id": "hashed" })
```

### Обоснование выбора
- **Равномерное распределение записей**: Избегает "горячих" точек при создании заказов
- **Эффективные запросы чтения**: Поиск истории заказов по клиенту выполняется на одном шарде
- **Балансировка нагрузки**: Гарантирует равномерное распределение данных и запросов по кластеру

### Дополнительные индексы
```javascript
db.orders.createIndex({ "customer_id": 1, "order_date": -1 })
db.orders.createIndex({ "status": 1 })
db.orders.createIndex({ "geo_zone": 1 })
```

---

## Коллекция `products`

### Схема документа
```javascript
{
  "_id": ObjectId,
  "name": String,
  "category": String,
  "price": Number,
  "stock": {
    "Екатеринбург": 50,
    "Калининград": 30
  },
  "attributes": {
    "color": String,
    "size": String
  },
  "createdAt": Date,
  "updatedAt": Date
}
```

### Стратегия шардирования
**Диапазонное шардирование по составному ключу `{category: 1, _id: 1}`**

```javascript
sh.shardCollection("ecommerce.products", { "category": 1, "_id": 1 })
```

### Обоснование выбора
- **Локализация данных**: Товары одной категории физически расположены близко
- **Эффективные запросы**: Поиск по категориям и фильтрация по цене выполняются на минимальном количестве шардов
- **Хорошая балансировка**: Включение `_id` обеспечивает равномерное распределение внутри категорий

### Дополнительные индексы
```javascript
db.products.createIndex({ "category": 1, "price": 1 })
db.products.createIndex({ "attributes.color": 1 })
db.products.createIndex({ "attributes.size": 1 })
```

---

## Резюме стратегий шардирования

| Коллекция | Шард-Ключ | Стратегия | Основное преимущество |
|-----------|-----------|-----------|----------------------|
| **carts** | `{user_id, session_id}` | Диапазонная | Локализация операций с корзинами |
| **orders** | `customer_id` | Хеш-шардирование | Равномерное распределение записей и эффективные запросы по клиентам |
| **products** | `{category, _id}` | Диапазонная | Эффективные запросы по категориям с хорошей балансировкой |

Все выбранные стратегии обеспечивают оптимальную производительность для наиболее частых операций чтения и записи, соответствующих бизнес-логике приложения электронной коммерции.