# Задание 10: Миграция на Cassandra — модель данных, репликация и консистентность

**Версия:** 1.1 (final)  
**Дата:** 12.10.2025  
**Проект:** Онлайн-магазин «Мобильный мир»

---

## Контекст
Во время пиков (Black Friday) кластер MongoDB с range‑sharding демонстрировал рост p95 из‑за перетаскивания больших объёмов данных при масштабировании. Требуется спроектировать миграцию ключевых сущностей на **Apache Cassandra**: модель (PK/CK, денормализация), репликация и уровни консистентности, механизмы целостности, предотвращение «горячих» партиций.

---

## Ключевые правила Cassandra‑дизайна (референс‑мемо)
1) **Partition key** — высокая кардинальность и равномерность распределения.  
2) **Clustering key** — порядок в пределах партиции (диапазоны, сортировка).  
3) **Денормализация** — отдельная таблица под каждый основной паттерн чтения.  
4) **Time‑bucketing** — защита от «hot» по геозонам/времени (день/час).

---

## 10.1 Что переносим и почему

| Сущность | Свежесть | Нагрузка | Гео | Характер | Решение |
|---|---|---|---|---|---|
| **Products (инвентарь)** | **Высокая** | Средняя | Да | Частые декременты | **Оставить в MongoDB** (ACID/сериализация) |
| **Orders** | Средняя | Write‑heavy | Да | Append‑mostly | **Cassandra** |
| **Carts** | Низкая–средняя | Write‑heavy | Локально | TTL/частые апдейты | **Cassandra** |
| **Order Events (аудит)** | Средняя | Append‑only | Да | Time‑series | **Cassandra** |
| **User Sessions** | Низкая | Read‑heavy | Локально | TTL 24h | **Cassandra** |

**Почему Cassandra:** leaderless R/W, **consistent hashing** (при scale‑out перераспределяется ~1/N данных), линейная масштабируемость, **tunable consistency**, TTL «из коробки». Инвентарь требует строгой сериализации — остаётся в MongoDB (или в сервисе резервирования).

---

## 10.2 Модель и схемы (query‑first, PK/CK, защита от «hot»)

### Keyspace и репликация
```cql
-- 2 DC (eu1, us1); RF на доступность и локальные чтения
CREATE KEYSPACE mobile_world WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'eu1': '3', 'us1': '3'
} AND durable_writes = true;
```

### Общие UDT
```cql
CREATE TYPE order_item (product_id text, name text, quantity int, price decimal);
CREATE TYPE address    (city text, street text, zip text);
CREATE TYPE cart_item  (product_id text, quantity int, added_at timestamp);
```

### A. Orders — три таблицы под основные запросы
**Паттерны:** история пользователя ↓ по дате; аналитика по геозоне×дню; быстрый lookup по `order_id`.

```cql
-- История пользователя
CREATE TABLE orders_by_user (
  user_id text,
  order_date timestamp,
  order_id text,
  geozone text,
  status text,
  total_amount decimal,
  items list<frozen<order_item>>,
  shipping_address frozen<address>,
  created_at timestamp,
  updated_at timestamp,
  PRIMARY KEY (user_id, order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC, order_id ASC)
  AND compaction = {'class':'LeveledCompactionStrategy'};

-- Lookup по id
CREATE TABLE orders_by_id (
  order_id text PRIMARY KEY,
  user_id text,
  order_date timestamp,
  geozone text,
  status text,
  total_amount decimal,
  items list<frozen<order_item>>,
  shipping_address frozen<address>,
  created_at timestamp,
  updated_at timestamp
) WITH compaction = {'class':'LeveledCompactionStrategy'};

-- Аналитика по геозоне × дню (time‑series)
CREATE TABLE orders_by_geozone (
  geozone text,
  date_bucket date,
  order_date timestamp,
  order_id text,
  user_id text,
  status text,
  total_amount decimal,
  PRIMARY KEY ((geozone, date_bucket), order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC, order_id ASC)
  AND compaction = {'class':'TimeWindowCompactionStrategy',
                    'compaction_window_size':'1',
                    'compaction_window_unit':'DAYS'};
```

**Защита от «горячих» партиций:**  
- `orders_by_user`: PK=`user_id` — высокая кардинальность; партиции компактные. VIP‑кейсы → лимит/архив.  
- `orders_by_geozone`: **composite PK** `(geozone, date_bucket)` разбивает «Москва» на 365+ партиций/год; при росте — добавить `hour_bucket`.  
- `orders_by_id`: по 1 записи на партицию — равномерно.

**Запись (денормализация):**
```cql
BEGIN BATCH
  INSERT INTO orders_by_user   (...) VALUES (...);
  INSERT INTO orders_by_id     (...) VALUES (...);
  INSERT INTO orders_by_geozone(...) VALUES (...);
APPLY BATCH;  -- batch ≠ транзакция; требуются идемпотентность и ретраи
```

### B. Carts — две таблицы + LWT на checkout
```cql
-- Гостевые корзины
CREATE TABLE carts_by_session (
  session_id text PRIMARY KEY,
  user_id text,
  items list<frozen<cart_item>>,
  status text,
  created_at timestamp,
  updated_at timestamp
) WITH default_time_to_live = 604800  -- 7d
  AND compaction = {'class':'LeveledCompactionStrategy'};

-- Авторизованные корзины
CREATE TABLE carts_by_user (
  user_id text,
  status text,
  items list<frozen<cart_item>>,
  created_at timestamp,
  updated_at timestamp,
  PRIMARY KEY (user_id, status)
) WITH default_time_to_live = 604800
  AND compaction = {'class':'LeveledCompactionStrategy'};
```

- **PK:** `session_id` / `user_id` → высокая кардинальность, равномерность.  
- **LWT — только checkout** (линеаризация `active→ordered`):
```cql
UPDATE carts_by_user
SET status='ordered', updated_at=toTimestamp(now())
WHERE user_id='USR-1' AND status='active'
IF status='active';  -- LWT (Paxos)
```

### C. Order Events — time‑series аудит
```cql
CREATE TABLE order_events (
  order_id text,
  event_time timestamp,
  event_type text,
  old_status text,
  new_status text,
  user_id text,
  metadata map<text,text>,
  PRIMARY KEY (order_id, event_time)
) WITH CLUSTERING ORDER BY (event_time ASC)
  AND compaction = {'class':'TimeWindowCompactionStrategy',
                    'compaction_window_size':'7',
                    'compaction_window_unit':'DAYS'};
```

### D. User Sessions — TTL‑хранилище
```cql
CREATE TABLE user_sessions (
  session_id text PRIMARY KEY,
  user_id text,
  device_info text,
  ip_address inet,
  last_activity timestamp,
  created_at timestamp
) WITH default_time_to_live = 86400  -- 24h
  AND compaction = {'class':'LeveledCompactionStrategy'};
```

---

## Быстрые SELECT‑примеры (референс)
```cql
-- Последние 20 заказов пользователя
SELECT order_id, order_date, status, total_amount
FROM orders_by_user WHERE user_id=? LIMIT 20;

-- Окно по зоне за день
SELECT order_id, order_date, total_amount
FROM orders_by_geozone WHERE geozone=? AND date_bucket=? LIMIT 500;

-- Деталь заказа
SELECT * FROM orders_by_id WHERE order_id=?;

-- Активная корзина пользователя
SELECT items FROM carts_by_user WHERE user_id=? AND status='active' LIMIT 1;
```

---

## 10.3 Репликация, консистентность, целостность

### Уровни консистентности по операциям
| Операция | Write CL | Read CL | Комментарий |
|---|---|---|---|
| Orders (создание) | QUORUM | QUORUM/ONE | История может читаться ONE; критичные пути — QUORUM |
| Orders (lookup by id) | QUORUM | QUORUM | Точность статуса |
| Carts add/remove | ONE | ONE | Минимальная latency |
| Carts checkout | QUORUM + **LWT** | QUORUM | Атомарная смена состояния |
| Order Events | ONE | ONE | Append‑only |
| User Sessions | LOCAL_ONE | LOCAL_ONE | Быстрые локальные проверки |

**Правило strong:** при `W + R > RF` достигается строгая консистентность; иначе — eventual. Для чтений используем **LOCAL_***, чтобы держать latency в пределах DC.

### Механизмы целостности
- **Hinted Handoff:** включён везде (`hinted_handoff_enabled:true`, `max_hint_window_in_ms` 1–3h).  
- **Read Repair:** для Orders на «сильных» чтениях (QUORUM) — догоняем отставшие реплики. Для Carts/Sessions — rely on TTL/eventual.  
- **Anti‑Entropy Repair:** планово `nodetool repair` (streaming в фоне):  
  ```bash
  # Weekly — Orders
  0 2 * * 0  nodetool repair --full mobile_world orders_by_user orders_by_id orders_by_geozone
  # Bi‑weekly — Order Events
  0 2 1,15 * * nodetool repair --full mobile_world order_events
  # Monthly/Quarterly — Carts/Sessions
  ```

---

## Масштабирование и «решардинг» (концептуально, без гипербол)
- **Cassandra:** при добавлении ноды перераспределяется **часть** ключевого диапазона (vnodes/consistent hashing) — ≈1/N данных к/от каждой ноды; стриминг в фоне, без «тотальной перешивки».  
- **MongoDB range‑sharding:** балансировщик переносит **многие chunks** при нарушении равномерности/зон; объём зависит от ключа/зон/числа шаров и **не сводится к универсальной формуле**. Практически — возможен рост p95 на время масштабирования.

---

## Итог
- **Переносим:** Orders, Carts, Order Events, Sessions → Cassandra; Products (инвентарь) — остаётся в MongoDB.  
- **Модель:** PK/CK под запросы, денормализация, bucketing; compaction LCS/TWCS, TTL, UDT.  
- **Консистентность/целостность:** RF=3 per DC, LOCAL_* чтения; CL по операциям; LWT только для checkout; Hinted Handoff + Read Repair (точечно) + плановые Repairs.  
- **Горячие партиции:** высококардинальные PK и bucketing по времени/зоне.

**Статус:** Готово к сдаче
