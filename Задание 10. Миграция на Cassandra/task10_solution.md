# Архитектура миграции на Cassandra для интернет-магазина

## Задание 10.1. Выбор критически важных данных для Cassandra

### Данные для переноса в Cassandra:

**Заказы (orders)**
- Высокая скорость записи в пиковые нагрузки
- Временные данные, идеально для time-series паттерна
- Append-only операции с редкими обновлениями статусов
- Геораспределённость по регионам

**Корзины (carts)**
- Высокая частота операций добавления/удаления товаров
- Временные данные с TTL
- Session-based, нет сложных транзакций
- Низкие требования к целостности

**История заказов**
- Read-heavy нагрузка для аналитики
- Архивные данные с естественным разделением по времени
- Допустима eventual consistency

### Данные для оставления в MongoDB:

**Товары (products)**
- Требуется строгая целостность остатков (анти-овербукинг)
- Сложные атомарные операции проверки и списания
- Относительно небольшой объём данных
- Частые обновления одних записей

## Задание 10.2. Модель данных Cassandra

### 1. Таблица orders_by_user
```cql
CREATE TABLE orders_by_user (
    user_id text,
    created_at timestamp,
    order_id text,
    geo_zone text,
    status text,
    total_amount decimal,
    items list<frozen<map<text, text>>>,
    shipping_address text,
    updated_at timestamp,
    PRIMARY KEY (user_id, created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```
**Обоснование:**
- Partition Key: `user_id` - высокая кардинальность, равномерное распределение
- Clustering Keys: `created_at DESC, order_id` - сортировка новых заказов первыми
- Оптимизация для запросов истории заказов пользователя

### 2. Таблица orders_by_id
```cql
CREATE TABLE orders_by_id (
    order_id text PRIMARY KEY,
    user_id text,
    created_at timestamp,
    geo_zone text,
    status text,
    total_amount decimal,
    items list<frozen<map<text, text>>>,
    shipping_address text,
    updated_at timestamp
);
```
**Обоснование:**
- Partition Key: `order_id` - быстрый доступ к конкретному заказу
- Равномерное распределение по UUID

### 3. Таблица carts_by_user
```cql
CREATE TABLE carts_by_user (
    user_id text,
    status text,
    cart_id timeuuid,
    items list<frozen<map<text, text>>>,
    created_at timestamp,
    updated_at timestamp,
    expires_at timestamp,
    PRIMARY KEY (user_id, status, cart_id)
) WITH CLUSTERING ORDER BY (status ASC, cart_id DESC)
  AND default_time_to_live = 604800; -- TTL 7 дней
```
**Обоснование:**
- Partition Key: `user_id` - все корзины пользователя в одной партиции
- Clustering Keys: `status, cart_id` - быстрый доступ к активной корзине

### 4. Таблица carts_by_session
```cql
CREATE TABLE carts_by_session (
    session_id text,
    status text,
    cart_id timeuuid,
    items list<frozen<map<text, text>>>,
    created_at timestamp,
    updated_at timestamp,
    expires_at timestamp,
    PRIMARY KEY (session_id, status, cart_id)
) WITH CLUSTERING ORDER BY (status ASC, cart_id DESC)
  AND default_time_to_live = 604800; -- TTL 7 дней
```
**Обоснование:**
- Отдельная таблица для гостевых сессий
- Автоматическая очистка через TTL

## Задание 10.3. Стратегии обеспечения целостности

### Заказы (orders_by_user, orders_by_id)
**Consistency Level:** QUORUM
```cql
INSERT INTO orders_by_user (...) USING CONSISTENCY QUORUM;
```

**Hinted Handoff:** ENABLED (окно 3 часа)
```yaml
hinted_handoff_enabled: true
max_hint_window_in_ms: 10800000
```

**Read Repair:** ENABLED (10%)
```cql
ALTER TABLE orders_by_user 
WITH read_repair_chance = 0.1;
```

**Anti-Entropy Repair:** Еженедельно
```bash
0 2 * * 0 nodetool repair -pr orders_by_user
```

### Корзины (carts_by_user, carts_by_session)
**Consistency Level:** ONE (запись) / LOCAL_QUORUM (чтение)
```cql
UPDATE carts_by_user USING CONSISTENCY ONE;
SELECT ... USING CONSISTENCY LOCAL_QUORUM;
```

**Hinted Handoff:** ENABLED (окно 1 час)

**Read Repair:** DISABLED
```cql
ALTER TABLE carts_by_user 
WITH read_repair_chance = 0.0;
```

**Anti-Entropy Repair:** Ежемесячно
```bash
0 3 1 * * nodetool repair -pr carts_by_user
```

## Преимущества архитектуры

- **Равномерное распределение:** Высокая кардинальность partition keys предотвращает горячие партиции
- **Быстрое масштабирование:** Consistent hashing перемещает только 1/N данных при добавлении узлов
- **Отказоустойчивость:** Leaderless репликация с RF=3
- **Геораспределённость:** Данные заказов распределены по регионам
- **Автоматическая очистка:** TTL для временных данных (корзины, сессии)