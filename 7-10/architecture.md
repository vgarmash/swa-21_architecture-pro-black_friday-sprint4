# Задание 7. Проектирование схем коллекций для шардирования данных

## 1. Коллекция orders
```
{
  _id: Object ID,
  user_id: Object ID, 
  created_at : Timestamp,
  items : [
      {
        product_id: Object ID,
        price: Double
      }
  ],
  total_sum: Double,
  geo_zone: Object ID
}

```
### Шард-ключ: 
geo_zone + _id (составной хешированный)

### Стратегия: 
Хэшированное шардирование

### Обоснование:
Равномерное распределение заказов по шардам, так как geo_zone часто используется в запросах.

_id добавляется для уникальности и предотвращения «горячих» шардов.

Операции создания заказов будут распределены равномерно.

### Пример команды:


``` 
sh.shardCollection("somedb.orders", { "geo_zone": 1, "_id": 1 }, { hashed: true }); 
```

## 2. Коллекция products

```
{
  _id: Object ID,
  name: String, 
  category : String,
  price: Double,
  price: Double,
  stocks : [
      {
        geo_zone: Object ID
        quantity: Integer
      }
  ],
  attributes: {
    color: String,
    size: String,
    ...
  }
}

```

### Шард-ключ:
category + price (диапазонный)

### Стратегия: 
Диапазонное шардирование

### Обоснование:
Частые запросы по категориям (category) и фильтрация по цене (price).

Позволяет эффективно распределять нагрузку: например, «Электроника» может быть на одном шарде, «Книги» — на другом.

### Пример команды:

```
sh.shardCollection("somedb.products", { "category": 1, "price": 1 });
```

## 3. Коллекция carts

```
{
  _id: Object ID,
  user_id: Object ID,
  session_id: String,
  items : [
      {
        product_id: Object ID,
        quantity: Integer
      }
  ],
  status: String,
  created_at : Timestamp,
  updated_at : Timestamp,
  expires_at : Timestamp
}

```
### Шард-ключ: 
user_id (хешированный)

### Стратегия: 
Хэшированное шардирование

### Обоснование:
Запросы к корзинам идут по user_id или session_id.

Гарантирует равномерное распределение, учитывая активность пользователей.

TTL-индекс на expires_at для автоматической очистки.

Пример команды:

```
sh.shardCollection("somedb.carts", { "user_id": "hashed" }); 
db.carts.createIndex({ "expires_at": 1 }, { expireAfterSeconds: 0 }); 
```


# Задание 8. Выявление и устранение «горячих» шардов

## Метрики:

1. Количество операций на шард:

    ```
   db.adminCommand({ listShards: 1 }).shards → анализ operationCounters.
    ```

2. Проверка неравномерности чанков: sh.status() 

3. Профилирование медленных запросов: db.setProfilingLevel(1, { slowms: 50 }).

4. Нагрузка CPU, RAM: mongodb_mongod_metrics_cpu_usage


## Механизмы перераспределения:
- Ребалансировка чанков:

```
sh.disableBalancing("somedb.products");
sh.moveChunk("somedb.products", { category: "Электроника" }, "shard2");
sh.enableBalancing("somedb.products"); 
```
- Изменение шард-ключа:
Переход на составной ключ, например, category + brand.
- Добавление новых шардов

# Задание 9. Настройка чтения с реплик и консистентность

| Коллекция    | Операция                       | Чтение с   | Обоснование выбора                                                                            | Допустимая задержка |
| ------------ |--------------------------------|------------|-----------------------------------------------------------------------------------------------|---------------------|
| products | Каталог товаров                | secondary  | Не критично, если данные немного устарели.                                                    | < 5 секунд          |
| products | Просмотр карточки товара       | secondary  | Для улучшения масштабируемости. Если TTL обновления < задержки, можно переключать на primary. | < 3 секунды         |
| products | Списаниме со склада            | primary    | Высокие требования к консистентности. Возможна отмена заказов из-за несогласованности         | 0                   |
| orders   | Список заказов пользователя    | primary    | Критично. Все статусы по заказам должны быть актуальные                                       | 0                   |
| orders   | Получение информации по заказу | primary    | Консистентность критична. Пользователь должен видеть актуальную информацию                    | 0                   |
| carts    | Корзина                        | primary    | Критично, т.к. stateful - необходимо поддерживать актуальность на всех устройствах            | 0                   |
| carts    | История заказов, аналитика     | secondary  | Не критична.                                                                                  | < 1 минуты          |


# Задание 10. Миграция на Cassandra: модель данных, стратегии репликации и шардирования

## 10.1:

### 1. Carts и сессии пользователей:

Требуют высокой скорости записи/чтения и отказоустойчивости. Cassandra отлично подходит под быстрое хранение и TTL данных по session_id.

### 2. Orders:

Заказы часто создаются и редко изменяются. Cassandra подходит для write-heavy сценариев.


### 3. Products:

Cassandra не подходит для сложной фильтрации и агрегирования. Лучше оставить в MongoDB или использовать другую OLAP-БД.


## 10.2 Модель данных в Cassandra:

### orders
```
CREATE TABLE orders (
    user_id UUID,
    order_id UUID,
    created_at timestamp,
    total_amount decimal,
    status text,
    geo_zone text,
    items list<frozen<item>>,
    PRIMARY KEY (user_id, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```
- Partition key: user_id — распределение на пользователей.
- Clustering key: order_id (или created_at) — для сортировки по дате создания.

### carts
```
CREATE TABLE carts (
    cart_id UUID,
    updated_at timestamp,
    user_id UUID,
    status text,
    items list<frozen<item>>,
    expires_at timestamp,
    PRIMARY KEY (session_id)
) WITH default_time_to_live = 86400; -- 1 день
```
- Partition key: cart_id — уникальный идентификатор корзины.
- Используем TTL, чтобы автоматически удалять устаревшие корзины.

### user_sessions
```
CREATE TABLE user_sessions (
    session_id UUID,
    user_id UUID,
    created_at timestamp,
    expires_at timestamp,
    PRIMARY KEY (session_id)
) WITH default_time_to_live = 3600; -- 1 час
```
- Partition key: session_id
- TTL для автоматического удаления сессий.

### order_history
```
CREATE TABLE order_history (
    user_id UUID,
    order_id UUID,
    status text,
    created_at timestamp,
    total_amount decimal,
    PRIMARY KEY (user_id, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC);
```

- Partition key: order_id
- Clustering key: created_at


## 10.3 Стратегии целостности:

1. Hinted Handoff: Для orders, carts, sessions 
   - Минимизирует потери при кратковременных отказах.

2. Read Repair: Для order_history
   - Фоновая проверка целостности при чтении
   - Идеально подходит для редко читаемых данных.

3. Anti-Entropy Repair: Для всех сущностей
   - Периодическая проверка целостности.
   - Регулярная фоновая синхронизация данных между репликами (например, ночью).
