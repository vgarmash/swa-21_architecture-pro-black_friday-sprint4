# task10_cassandra

Цель: определить, что переносить в Cassandra, спроектировать модель (partition/cluster keys) и описать стратегии целостности.

## 10.1 Что переносим и почему
Критичные по масштабу и нагрузке сущности:
- **events_order_status** (журнал статусов заказов) — write-heavy (append‑only), time-series; нужны быстрые записи и горизонтальное масштабирование.
- **cart_events** (события корзин) — поток кликов/изменений, аналитика сессий; высокий TPS, eventual consistency допустима.
- **product_stock_events** (изменения остатков) — поток инкрементов/декрементов по геозонам; запись при каждой покупке/резервировании.

Оставляем в MongoDB:
- Транзакционные документы «истины» (`orders`, `products`, `carts`) — оперативная модель и гибкие запросы.

Почему Cassandra:
- Linear scale-out на запись, низкая латентность под пиковую нагрузку.
- Геораспределённость, настройка уровня консистентности.
- Отсутствие глобальных блокировок/перешардирования при росте.

## 10.2 Концептуальная модель и ключи
Принципы: проектировать под запросы, избегать ALLOW FILTERING, денормализовать под нужные сечения.

### Таблица 1: events_order_status
Запросы:
- История статусов по заказу (основной путь).
- Последние события по геозоне/интервалу (оперативная витрина).

Модель:
```sql
CREATE TABLE IF NOT EXISTS events_order_status (
  order_id text,
  event_time timestamp,
  status text,
  geo text,
  payload text,
  PRIMARY KEY ((order_id), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```
- Partition: `order_id` — вся история заказа в одной партиции, быстрые range‑чтения.
- Clustering: `event_time DESC` для последних событий сверху.

Витрина по геозоне (денорм):
```sql
CREATE TABLE IF NOT EXISTS events_order_status_by_geo (
  geo text,
  day date,
  event_time timestamp,
  order_id text,
  status text,
  PRIMARY KEY ((geo, day), event_time, order_id)
) WITH CLUSTERING ORDER BY (event_time DESC);
```
- Partition: `(geo, day)` — контролируем размер; чтение «последние X минут по geo».

### Таблица 2: cart_events
Запросы:
- Лента событий корзины по `session_id` или `user_id`.

Модель:
```sql
CREATE TABLE IF NOT EXISTS cart_events (
  owner text,          -- session_id или user_id
  event_time timeuuid, -- для уникальности и сортировки
  type text,           -- add_item, remove_item, merge, checkout
  cart_id text,
  product_id text,
  quantity int,
  payload text,
  PRIMARY KEY ((owner), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```
- Partition: `owner` — все события сессии/пользователя последовательно и быстро.

### Таблица 3: product_stock_events
Запросы:
- Изменения остатков по `(product_id, geo)` за период.

Модель:
```sql
CREATE TABLE IF NOT EXISTS product_stock_events (
  product_id text,
  geo text,
  day date,
  event_time timeuuid,
  delta int,
  reason text,
  PRIMARY KEY ((product_id, geo, day), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```
- Partition: `(product_id, geo, day)` ограничивает размер и равномерно распределяет нагрузку.

Агрегат (опционально) для быстрых остатков:
```sql
CREATE TABLE IF NOT EXISTS product_stock_daily (
  product_id text,
  geo text,
  day date,
  total int,
  PRIMARY KEY ((product_id, geo), day)
) WITH CLUSTERING ORDER BY (day DESC);
```

## 10.3 Консистентность и стратегии восстановления

Уровни консистентности (пример):
- Запись: `LOCAL_QUORUM` (в пределах DC) для журналов; `ONE` допустим для cart_events при высокой нагрузке.
- Чтение: `LOCAL_QUORUM` для критичных отчётов; `ONE`/`LOCAL_ONE` для оперативных лент.

Стратегии:
- **Hinted Handoff**: включён для временно недоступных нод, снижает write‑loss при кратковременных сбоях.
- **Read Repair**: включить фоновые починки (`read_repair_chance` ≈ 0–0.1 в C* 4.x) для горячих таблиц; баланс между накладными расходами и свежестью.
- **Anti‑Entropy Repair**: регулярный `nodetool repair`/`reaper` по расписанию (например, ежедневно инкрементальный + полное еженедельно) для устранения дрейфа данных.

Политики:
- Для `events_order_status` и `product_stock_events`: записи `LOCAL_QUORUM`, чтения `LOCAL_QUORUM` для аналитики и `LOCAL_ONE` для realtime‑ленты.
- Для `cart_events`: записи `ONE`/`LOCAL_ONE` (приемлема eventual), чтения `LOCAL_ONE`.

## 10.4 Потоки данных и интеграция
- Источник событий: приложения/воркеры из MongoDB (outbox/CDC, change streams) → Kafka → консьюмеры C*.
- Идемпотентность на ключах `(partition, clustering)`; при повторе — upsert по тем же ключам.
- TTL на «хвосты» временных витрин (например, 7–30 дней) для управления размером.

## 10.5 Проверочные запросы
```sql
-- последние статусы заказа
SELECT * FROM events_order_status WHERE order_id = ? LIMIT 20;
-- события по гео за сегодня
SELECT * FROM events_order_status_by_geo WHERE geo = ? AND day = ? LIMIT 1000;
-- лента корзины
SELECT * FROM cart_events WHERE owner = ? LIMIT 200;
-- изменения остатков
SELECT * FROM product_stock_events WHERE product_id = ? AND geo = ? AND day = ? LIMIT 500;
``` 