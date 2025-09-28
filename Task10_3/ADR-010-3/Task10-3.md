### <a name="_b7urdng99y53"></a>**Название задачи:**
ADR-010-3: Стратегии обеспечения целостности данных в Cassandra
### <a name="_hjk0fkfyohdk"></a>**Автор:**
Архитектурная команда "Мобильный мир"
### <a name="_uanumrh8zrui"></a>**Дата:**
30.09.2025
### **Контекст и описание проблемы**
Необходимо выбрать оптимальные стратегии обеспечения целостности данных для каждой сущности, мигрируемой в Cassandra, с учетом требований к производительности и консистентности.

### <a name="_qmphm5d6rvi3"></a>**Решение**

#### 1. Обзор стратегий восстановления целостности

#### Характеристики стратегий

| Стратегия           | Когда срабатывает                      | Влияние на latency                   | Гарантии консистентности | Нагрузка на сеть |
|---------------------|----------------------------------------|--------------------------------------|--------------------------|------------------|
| Hinted Handoff      | При недоступности узла во время записи | Минимальное (асинхронно)             | Eventual consistency     | Низкая           |
| Read Repair         | При чтении с CL < ALL                  | Увеличивает latency чтения на 10-20% | Постепенное улучшение    | Средняя          |
| Anti-Entropy Repair | По расписанию (cron)                   | Не влияет на запросы                 | Полная консистентность   | Высокая          |

#### 2. Стратегии для корзин (carts)

#### Конфигурация таблицы
```cql
CREATE TABLE carts (
    session_id UUID,
    updated_at timestamp,
    product_id UUID,
    user_id UUID,
    quantity int,
    price decimal,
    product_name text,
    PRIMARY KEY ((session_id), updated_at, product_id)
) WITH 
    default_time_to_live = 2592000
    AND read_repair_chance = 0.1      -- 10% вероятность read repair
    AND dclocal_read_repair_chance = 0.2  -- 20% для локального DC
    AND gc_grace_seconds = 86400;     -- 1 день для tombstones
```

#### Выбранные стратегии

Основная: Hinted Handoff
```yaml
# cassandra.yaml
hinted_handoff_enabled: true
max_hint_window_in_ms: 10800000  # 3 часа хранения хинтов
```

Дополнительная: Read Repair (10%)
```cql
-- Настройка на уровне таблицы
ALTER TABLE carts WITH read_repair_chance = 0.1;
```

#### Обоснование
* Корзины живут максимум 30 дней, нет смысла в полном repair
* Небольшая задержка синхронизации некритична
* Если корзина не синхронизировалась 3 часа, вероятно она уже неактуальна

#### 3. Стратегии для сессий пользователей

#### Конфигурация таблицы
```cql
CREATE TABLE user_sessions (
    bucket int,
    session_id UUID,
    user_id UUID,
    created_at timestamp,
    last_activity timestamp,
    session_data map<text, text>,
    PRIMARY KEY ((bucket), session_id)
) WITH 
    default_time_to_live = 86400
    AND read_repair_chance = 0.0      -- Отключен
    AND dclocal_read_repair_chance = 0.1  -- 10% локально
    AND gc_grace_seconds = 3600;      -- 1 час для tombstones
```

#### Выбранные стратегии

Основная: Hinted Handoff с агрессивным TTL
```yaml
# Специальная конфигурация для сессий
hinted_handoff_throttle_in_kb: 1024
max_hints_delivery_threads: 4
hints_flush_period_in_ms: 5000  # Быстрая доставка хинтов
```

Read Repair: Минимальный (только локальный DC)
```cql
ALTER TABLE user_sessions 
    WITH dclocal_read_repair_chance = 0.1
    AND read_repair_chance = 0.0;
```

#### Обоснование
* TTL 24 часа делает repair бессмысленным
* 90% операций - запись, read repair неэффективен
* Read repair увеличил бы задержку аутентификации
* Потеря сессии = повторный логин (минимальный ущерб)

### 4. Стратегии для истории заказов

#### Конфигурация таблицы
```cql
CREATE TABLE order_history (
    customer_id UUID,
    time_bucket text,
    created_at timestamp,
    order_id UUID,
    total_amount decimal,
    status text,
    items frozen<list<frozen<order_item>>>,
    PRIMARY KEY ((customer_id, time_bucket), created_at, order_id)
) WITH 
    read_repair_chance = 0.2          -- 20% вероятность
    AND dclocal_read_repair_chance = 0.3  -- 30% локально
    AND gc_grace_seconds = 864000;    -- 10 дней
```

#### Выбранные стратегии

Основная: Anti-Entropy Repair (еженедельно)
```bash
#!/bin/bash
# repair_order_history.sh - запускается через cron
nodetool repair -pr -inc \
    mobileworld order_history \
    -st ${START_TOKEN} \
    -et ${END_TOKEN}
```

Дополнительная: Read Repair (25%)
```cql
-- Более агрессивный read repair для важных данных
ALTER TABLE order_history WITH read_repair_chance = 0.25;
```

Hinted Handoff: Расширенное окно
```yaml
# Для истории заказов - длительное хранение хинтов
max_hint_window_in_ms: 86400000  # 24 часа
```

#### Обоснование
* История хранится годами, требует периодического repair
* Финансовые данные должны быть точными
* Можно реализовать overhead от read repair
* Требования регуляторов к целостности финансовых данных

### 5. Оптимизация Consistency Levels

#### Матрица выбора уровней консистентности

| Операция         | Корзины      | Сессии  | История заказов | Обоснование                  |
|------------------|--------------|---------|-----------------|------------------------------|
| Запись           | ONE          | ONE     | LOCAL_QUORUM    | Баланс скорости и надежности |
| Чтение обычное   | ONE          | ONE     | LOCAL_ONE       | Максимальная скорость        |
| Чтение критичное | LOCAL_QUORUM | ONE     | LOCAL_QUORUM    | Гарантия актуальности        |

## Преимущества выбранного подхода

1. Дифференцированный подход: каждая сущность получает оптимальную стратегию в результате дифференцированного подхода
2. Критичные операции не замедляются из-за минимального влияния на latency
3. Существенная экономия ресурсов вследствие отказа от repair для временных данных
4. Соответствие требованиям: история заказов имеет гарантии для аудита

### <a name="_bjrr7veeh80c"></a>**Альтернативы**

1. Максимальная консистентность

Причина отказа: неприемлемое многократное увеличение latency

2. Полный отказ от repair стратегий

Причина отказа: накопление несогласованности до критического уровня

3. Continuous repair для всех таблиц

Причина отказа: избыточная нагрузка на временные данные (80% таблиц с TTL)

**Недостатки, ограничения, риски**

| Риск                                 | Митигация                                    |
|--------------------------------------|----------------------------------------------|
| Накопление несогласованности         | Мониторинг и алертинг при превышении порогов |
| Потеря хинтов при сбое               | Репликация хинтов на несколько узлов         |
| Задержка repair после сбоя           | Приоритизация критичных таблиц               |
| Влияние repair на производительность | Выполнение в окна минимальной нагрузки       |
