# task9_read_prefs_consistency

Цель: определить политику чтения (primary/secondary), допустимую задержку репликации и обоснование для `products`, `orders`, `carts`.

## Таблица операций → источник чтения

| Коллекция | Операция | Read Preference | Доп. условия |
|---|---|---|---|
| products | Каталог (список по категории, фильтры по цене) | secondaryPreferred | Допустим лаг до 1–2 сек; при недоступности secondary — чтение с primary |
| products | Карточка товара | secondaryPreferred | Если stock критичен — делаем read concern majority + fallback на primary |
| products | Остатки по геозоне (на витрину) | primaryPreferred | При риске oversell лучше брать с primary или из кэша |
| orders | История заказов пользователя | primary | Данные чувствительны к консистентности |
| orders | Отображение статуса заказа | primary | Допустимо majority; лаг нежелателен |
| carts | Получить активную корзину {owner,status:"active"} | primaryPreferred | Лаг ≤ 500 мс; иначе риск рассинхронизации при добавлении товара |
| carts | Просмотр корзины (read-only) | secondaryPreferred | Для страницы можно читать с secondary при лаге ≤ 500 мс |

## Допустимая задержка репликации
- products: до 1–2 сек для большинства чтений; для остатков на критичных шагах — 0 сек (primary/majority).
- orders: 0–0.5 сек (де-факто primary); статус/история должны быть консистентны.
- carts: ≤ 0.5 сек. На операциях изменения — чтение с primary.

## Обоснование
- **products** обновляются часто по остаткам, но большинство чтений терпит слабую консистентность; переносим нагрузку на secondary, критичные точки — primary.
- **orders** — финансовая запись; ошибки консистентности недопустимы → читаем с primary.
- **carts** — интерактивная сущность; при модификациях — strict, при простом просмотре возможна eventual.

## Примеры настроек PyMongo

URI/клиенты:
```python
from pymongo import MongoClient, read_preferences

# products: secondaryPreferred + maxStalenessSeconds
products_client = MongoClient(
    "mongodb://router:27017/?replicaSet=rsA,rsB",
    readPreference="secondaryPreferred",
    maxStalenessSeconds=2
)

# orders: primary (по умолчанию)
orders_client = MongoClient("mongodb://router:27017/")

# carts: primaryPreferred с ограничением старалости
carts_client = MongoClient(
    "mongodb://router:27017/",
    readPreference="primaryPreferred",
    maxStalenessSeconds=1
)
```

Вызовы коллекций:
```python
products = products_client["somedb"]["products"]
orders = orders_client["somedb"]["orders"]
carts = carts_client["somedb"]["carts"]
```

Гранулярная настройка per‑query:
```python
from pymongo import ReadPreference

# Чтение карточки товара со secondary
products.with_options(read_preference=ReadPreference.SECONDARY_PREFERRED).find_one({"_id": pid})

# Критичное чтение остатков — только primary
products.with_options(read_preference=ReadPreference.PRIMARY).aggregate([
  {"$match": {"_id": pid}},
  {"$unwind": "$stock_by_zone"},
  {"$match": {"stock_by_zone.geo": geo}}
])

# История заказов — primary
orders.with_options(read_preference=ReadPreference.PRIMARY).find({"user_id": uid}).sort("created_at", -1)

# Просмотр корзины read-only — secondaryPreferred
carts.with_options(read_preference=ReadPreference.SECONDARY_PREFERRED, maxStalenessSeconds=1).find_one({
  "session_or_user": owner,
  "status": "active"
})
``` 