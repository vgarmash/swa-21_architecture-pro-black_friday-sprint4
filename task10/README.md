# Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

## 10.1 Выбор критичных сущностей

| Сущность               | Важность перехода (от 1 до 5) | Обоснование перехода на Cassandra                                                                  |
| ---------------------- |-------------| -------------------------------------------------------------------------------------------------- |
| **Orders (Заказы)** | 5 | Высокий объём insert-запросов в пике. Переход позволит избежать перераспределения шардов  |
| **Carts (Корзины)** | 5  | Возможен высокий всплеск insert-запросов. Переход позволит избежать перераспределения шардов |
| **Order History (история заказов)** | 3 | Это исторические данные, которые можно переносить из заказов в фоне/по ночам - без влияния на производительность |
| **Users (Пользователи)** | 3  | Редкая запись, редкие обновления. Можно перенести 2-3 приоритетом |
| **Products (Товары)** | 2  | Лучше оставить в MongoDB. Обновления редкие, большой объём данных. |
| **Sessions (Пользовательские сессии)** | 1  | Частая запись, но нет необходимости в целостности - главное отдавать актуальные корзины |

---

## 10.2. Определение ключей

| Таблица | Partition key | Cluster keys | Обоснование | 
|---------|---------------|------------|------------|
| Orders | `user_id` | `id`, `order_ts DESC`| Один и тот же юзер будет создавать большинство заказов из одной гео-зоны, потому есть смысл делить партиции по `user_id`. Так же критически важно получать последние заказы по времени |
| Carts | `geo_zone` | `user_id`, `session_id`, `created_at DESC` | партиции есть смысл сделать по гео-зонам, а в качестве ключей подойдут user_id/session_id - т.к по ним будет выполняться поиск |
| Order_History | `user_id` | `order_ts DESC`| Данные будут извлекаться по юзеру, дибо для отчетности |
| Users | `geo_zone` | `id`, `email` | Поиск данных чаще всего будет по emailю Партиционирование либо не нужно вовсе, либо может быть сделано по гео-зонам |

---

## 10.3. Целостность

| Таблица | Стратегия | Обоснование |
|---------|---------------|------------|
| Orders | Hinted Handoff + Anti-Entropy Repair | Консистентность очень важна, потому "Hinted Handoff". "Anti-Entropy Repair" позволит гарантировать целостность, если запускать его по ночам, для дополнительной гарантии |
| Carts | Read Repair | Нет необходимости максимальной консистентности. "Read Repair" подходит идеально |
| Order_History | Read Repair | Нет необходимости максимальной консистентности. "Read Repair" подходит идеально |
| Users | Read Repair + Anti-Entropy Repair  | Нет необходимости максимальной консистентности. Для надежности можно иногда запускать "Anti-Entropy Repair" |

## Запросы создания таблиц

Таблица **Orders**
```sql
CREATE TABLE orders (
    user_id UUID,
    id UUID,
    order_ts TIMESTAMP,
    items LIST<FROZEN<MAP<TEXT, TEXT>>>,
    status TEXT,
    total DECIMAL,
    geo_zone TEXT,
    created_at TIMESTAMP,
    PRIMARY KEY ((user_id), id, order_ts)
) WITH CLUSTERING ORDER BY (id ASC, order_ts DESC);

-- Индекс для поиска заказов по статусу
CREATE INDEX IF NOT EXISTS orders_status_idx ON orders (status);
```

Таблица **Carts**
```sql
CREATE TABLE carts (
    geo_zone TEXT,
    user_id UUID,
    session_id TEXT,
    id UUID,
    items LIST<FROZEN<MAP<TEXT, INT>>>,
    status TEXT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    expires_at TIMESTAMP,
    PRIMARY KEY ((geo_zone), user_id, session_id, updated_at)
) WITH CLUSTERING ORDER BY (user_id ASC, session_id ASC, updated_at DESC);
```

Таблица **Order_History**
```sql
CREATE TABLE order_history (
    user_id UUID,
    order_ts TIMESTAMP,
    order_id UUID,
    items LIST<FROZEN<MAP<TEXT, TEXT>>>,
    status TEXT,
    total DECIMAL,
    geo_zone TEXT,
    created_at TIMESTAMP,
    PRIMARY KEY ((user_id), order_ts, order_id)
) WITH CLUSTERING ORDER BY (order_ts DESC, order_id ASC);
```

Таблица **Users**
```sql
CREATE TABLE users (
    geo_zone TEXT,
    id UUID,
    email TEXT,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    PRIMARY KEY ((geo_zone), id, email)
) WITH CLUSTERING ORDER BY (id ASC, email ASC);
```
