# task7_schemas

Цель: спроектировать коллекции `products`, `orders`, `carts`, выбрать шард‑ключи и привести команды MongoDB.

## Общие принципы
- Используем UUID/ULID как `_id` (строка). Для шардирования избегаем монотонно растущих ключей.
- Все коллекции — компромисс между балансировкой нагрузки и локальностью запросов.
- Индексы покрывают основные фильтры и джоины на уровне приложения.

## products
Назначение: каталог товаров; частые чтения, обновление остатков по геозонам.

Схема (упрощённо):
```json
{
  "_id": "prod_...",
  "name": "string",
  "category": "string",
  "price": { "amount": number, "currency": "RUB" },
  "stock_by_zone": [ { "geo": "MSK", "qty": number }, ... ],
  "attrs": { "color": "black", "size": "M", ... },
  "updated_at": ISODate
}
```

Шард‑ключ: `{ category: 1, _id: "hashed" }`
- Почему:
  - Разбиваем по категориям для локальности выборок по каталогу.
  - Добавляем `hashed _id` для равномерного распределения внутри категории (миксуем горячие/холодные id).
- Индексы: `{ category: 1, price.amount: 1 }`, `{ "stock_by_zone.geo": 1 }`.

Команды:
```javascript
sh.enableSharding("somedb")
sh.shardCollection("somedb.products", { category: 1, _id: "hashed" })
db.products.createIndex({ category: 1, "price.amount": 1 })
db.products.createIndex({ "stock_by_zone.geo": 1 })
```

## orders
Назначение: заказы; критично быстрое создание и выборка истории по пользователю.

Схема:
```json
{
  "_id": "ord_...",
  "user_id": "usr_...",
  "created_at": ISODate,
  "items": [ { "product_id": "prod_...", "qty": number, "price": number, "category": "string" } ],
  "status": "created|paid|shipped|delivered|cancelled",
  "total": number,
  "geo": "MSK"
}
```

Шард‑ключ: `{ user_id: 1, created_at: -1 }`
- Почему:
  - Основная выборка — история одного пользователя: попадание на один шард, сортировка по времени эффективна.
  - Записи равномерны по пользователям; горячие пользователи распределены по множеству ключей.
- Индексы: `{ user_id: 1, created_at: -1 }` (совпадает с ключом), `{ status: 1, created_at: -1 }`.

Команды:
```javascript
sh.shardCollection("somedb.orders", { user_id: 1, created_at: -1 })
db.orders.createIndex({ status: 1, created_at: -1 })
```

## carts
Назначение: активные корзины (гостевые и пользовательские), быстрые чтение/запись, TTL для очистки.

Схема:
```json
{
  "_id": "cart_...",
  "user_id": "usr_..." | null,
  "session_id": "sess_..." | null,
  "items": [ { "product_id": "prod_...", "quantity": number } ],
  "status": "active|ordered|abandoned",
  "created_at": ISODate,
  "updated_at": ISODate,
  "expires_at": ISODate // TTL
}
```

Шард‑ключ: `{ status: 1, session_or_user: 1 }`
- В документе храним поле `session_or_user`: для `active` значением будет `user_id` или `session_id` (если пользователь не залогинен). Для неактивных значение можно копировать из момента закрытия.
- Почему:
  - Все операции поиска текущей корзины бьют по `{ status: "active", session_or_user: X }` и попадают на один шард.
  - Распределение равномерное, т.к. ключ — фактический идентификатор владельца.
- Индексы: `{ status: 1, session_or_user: 1 }` (unique, sparse для active), TTL: `{ expires_at: 1 }` с `expireAfterSeconds: 0`.

Команды:
```javascript
// подготовка поля с денормализацией на запись
sh.shardCollection("somedb.carts", { status: 1, session_or_user: 1 })
db.carts.createIndex({ status: 1, session_or_user: 1 }, { unique: true, partialFilterExpression: { status: "active" } })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

## Риски и альтернативы
- products: при «горячей» категории возможен дисбаланс — решается балансировкой чанков и добавлением префикса по геозоне: `{ category: 1, "stock_by_zone.geo": 1, _id: "hashed" }`.
- orders: мульти‑региональная аналитика по времени — можно добавить ретроспективный процесс агрегации в отдельную коллекцию/даталейк.
- carts: при массовых гостях используем `session_id` (длинный случайный ключ) — хорошо хешируется, не создаёт горячих чанков.

## Итоги
- Выбранные ключи соответствуют паттернам запросов и распределяют нагрузку.
- Команды позволяют воспроизвести конфигурацию шардирования и индексов. 

## Диаграммы (.puml)
- products: `products.puml`
- orders: `orders.puml`
- carts: `carts.puml`

Идеи по структуре и оформлению вдохновлены учебным репозиторием [`chashchinalex/architecture-pro-black_friday` (ветка work)](https://github.com/chashchinalex/architecture-pro-black_friday/blob/work). 