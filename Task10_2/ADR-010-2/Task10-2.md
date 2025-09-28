### <a name="_b7urdng99y53"></a>**Название задачи:**
ADR-010-1: Концептуальная модель данных и стратегия партиционирования для Cassandra
### <a name="_hjk0fkfyohdk"></a>**Автор:**
Архитектурная команда "Мобильный мир"
### <a name="_uanumrh8zrui"></a>**Дата:**
29.09.2025
### **Контекст и описание проблемы**
Необходимо разработать детальную модель данных с оптимальной стратегией партиционирования для обеспечения равномерного распределения нагрузки и предотвращения "горячих" партиций.

### <a name="_qmphm5d6rvi3"></a>**Решение**

### 1. Концептуальная модель для корзин (carts)

#### Структура данных и ключи
```cql
CREATE TABLE carts (
    session_id UUID,           -- Partition Key
    updated_at timestamp,       -- Clustering Key (1)
    product_id UUID,           -- Clustering Key (2)
    user_id UUID,
    quantity int,
    price decimal,
    product_name text,         -- Денормализация для быстрого чтения
    product_image_url text,    -- Денормализация
    status text,
    PRIMARY KEY ((session_id), updated_at, product_id)
) WITH CLUSTERING ORDER BY (updated_at DESC, product_id ASC)
  AND default_time_to_live = 2592000
  AND compaction = {'class': 'TimeWindowCompactionStrategy', 
                    'compaction_window_unit': 'DAYS',
                    'compaction_window_size': 1};
```

#### Обоснование выбора ключей
* Partition Key (session_id):
  * Обеспечивает равномерное распределение: UUID генерируется случайно для каждой сессии
  * Предотвращает "горячие" партиции: каждый пользователь работает со своей корзиной
  * Размер партиции ограничен: максимум ~100 товаров на корзину = ~10KB данных

* Clustering Keys (updated_at, product_id):
  * Сортировка по времени для быстрого получения последнего состояния
  * product_id предотвращает дубликаты при одновременных обновлениях

#### Паттерны доступа
```cql
-- Получение корзины пользователя
SELECT * FROM carts WHERE session_id = ? LIMIT 100;

-- Обновление товара в корзине
UPDATE carts SET quantity = ? WHERE session_id = ? 
  AND updated_at = ? AND product_id = ?;
```

### 2. Концептуальная модель для сессий пользователей

#### Основная таблица сессий
```cql
CREATE TABLE user_sessions (
    bucket int,                -- Partition Key (временное окно)
    session_id UUID,           -- Clustering Key
    user_id UUID,
    created_at timestamp,
    last_activity timestamp,
    ip_address inet,
    user_agent text,
    geo_zone text,
    session_data map<text, text>,
    PRIMARY KEY ((bucket), session_id)
) WITH default_time_to_live = 86400
  AND compaction = {'class': 'LeveledCompactionStrategy'};
```

#### Индексная таблица для поиска по user_id
```cql
CREATE TABLE sessions_by_user (
    user_id UUID,              -- Partition Key
    created_at timestamp,       -- Clustering Key
    session_id UUID,
    last_activity timestamp,
    device_type text,
    PRIMARY KEY ((user_id), created_at)
) WITH CLUSTERING ORDER BY (created_at DESC)
  AND default_time_to_live = 86400;
```

#### Стратегия bucketing для предотвращения горячих партиций
```shell
// Вычисление bucket для равномерного распределения
int calculateBucket(UUID sessionId) {
    // 100 buckets, распределение по хешу session_id
    return Math.abs(sessionId.hashCode()) % 100;
}

// Запись сессии
PreparedStatement insert = session.prepare(
    "INSERT INTO user_sessions (bucket, session_id, user_id, ...) " +
    "VALUES (?, ?, ?, ...) USING TTL 86400"
);
session.execute(insert.bind(
    calculateBucket(sessionId), sessionId, userId, ...
));
```

### 3. Концептуальная модель для истории заказов

#### Основная таблица с композитным partition key
```cql
CREATE TABLE order_history (
    customer_id UUID,          -- Partition Key (1)
    time_bucket text,          -- Partition Key (2) формат: 'YYYY-MM'
    created_at timestamp,       -- Clustering Key (1)
    order_id UUID,             -- Clustering Key (2)
    total_amount decimal,
    status text,
    delivery_address text,
    payment_method text,
    items list<frozen<order_item>>,
    PRIMARY KEY ((customer_id, time_bucket), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC)
  AND compaction = {'class': 'TimeWindowCompactionStrategy',
                    'compaction_window_unit': 'DAYS',
                    'compaction_window_size': 30};

-- UDT для товаров в заказе
CREATE TYPE order_item (
    product_id UUID,
    product_name text,
    quantity int,
    price decimal
);
```

#### Глобальный индекс для поиска по периодам
```cql
CREATE TABLE orders_by_period (
    time_bucket text,          -- Partition Key ('YYYY-MM-DD')
    created_at timestamp,       -- Clustering Key
    order_id UUID,
    customer_id UUID,
    total_amount decimal,
    PRIMARY KEY ((time_bucket), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

### 4. Анализ и предотвращение "горячих" партиций

#### Метрики мониторинга
```cql
-- Таблица для отслеживания размеров партиций
CREATE TABLE partition_stats (
    table_name text,
    partition_key text,
    size_bytes bigint,
    row_count bigint,
    last_updated timestamp,
    PRIMARY KEY ((table_name), partition_key)
);
```

#### Стратегии предотвращения горячих партиций

| Проблема                       | Решение            | Реализация                               |
|--------------------------------|--------------------|------------------------------------------|
| Популярная корзина             | Не актуально       | UUID session_id гарантирует уникальность |
| Всплеск сессий                 | Bucketing          | 100 buckets распределяют нагрузку        |
| Массовые заказы одного клиента | Time bucketing     | Разделение по месяцам (YYYY-MM)          |
| Пиковые периоды (Black Friday) | Adaptive bucketing | Динамическое увеличение buckets          |

### <a name="_bjrr7veeh80c"></a>**Альтернативы**

1. Простое партиционирование без bucketing

Причина отказа:
   * Все данные сессии в одной партиции могут превысить рекомендуемые 100MB
   * Map-структура требует перезаписи всей партиции при изменении
   * Отсутствие истории изменений, т.к. невозможно отследить эволюцию корзины
   * Потеря данных при одновременных обновлениях

2. Глобальное партиционирование по времени

Причина отказа:
   * Горячие партиции в пиковые часы
   * Требуется сканировать множество партиций
   * Сложность определения оптимального временного окна
   * Неравномерная нагрузка по времени суток

**Недостатки, ограничения, риски**

| Риск                                            | Митигация                              |
|-------------------------------------------------|----------------------------------------|
| Рост размера партиций со временем               | TTL и time-bucketing                   |
| Неравномерность из-за популярных пользователей  | Мониторинг и адаптивный bucketing      |
| Потеря данных при сбое                          | RF=3 и multi-DC репликация             |
| Сложность запросов по вторичным атрибутам       | Materialized views и индексные таблицы |

