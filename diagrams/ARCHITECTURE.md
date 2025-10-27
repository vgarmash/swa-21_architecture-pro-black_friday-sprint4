# Архитектура MongoDB Sharding Optimization

> 📊 Этот документ содержит визуализацию всех архитектурных схем с интерактивным рендерингом  
> 🏠 [← Вернуться к README](../README.md) | 📖 [Подробное планирование →](../PLANNING.md)

## Схема 1: Базовое шардирование

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Web Browser]
    end

    subgraph "Application Layer"
        API[pymongo-api<br/>Flask Application]
    end

    subgraph "MongoDB Sharded Cluster"
        mongos[mongos<br/>Query Router]
        
        subgraph "Config Servers"
            configSrv1[configSrv1<br/>Config Server]
            configSrv2[configSrv2<br/>Config Server]
            configSrv3[configSrv3<br/>Config Server]
        end
        
        subgraph "Shard 1"
            shard1[shard1<br/>Primary Shard 1]
        end
        
        subgraph "Shard 2"
            shard2[shard2<br/>Primary Shard 2]
        end
    end

    Client -->|HTTP| API
    API -->|MongoDB Protocol| mongos
    mongos -->|Metadata| configSrv1
    mongos -->|Metadata| configSrv2
    mongos -->|Metadata| configSrv3
    mongos -->|Data Queries| shard1
    mongos -->|Data Queries| shard2

    style API fill:#4CAF50
    style mongos fill:#FF9800
    style configSrv1 fill:#2196F3
    style configSrv2 fill:#2196F3
    style configSrv3 fill:#2196F3
    style shard1 fill:#9C27B0
    style shard2 fill:#9C27B0
```

### Компоненты:
- **pymongo-api** - Flask приложение
- **mongos** - Query Router для маршрутизации запросов
- **configSrv1, configSrv2, configSrv3** - Config Servers для хранения метаданных кластера
- **shard1, shard2** - Шарды для хранения данных

### Сетевые взаимодействия:
- Client → API (HTTP)
- API → mongos (MongoDB Protocol)
- mongos → Config Servers (Metadata queries)
- mongos → Shards (Data queries)

---

## Схема 2: Шардирование + Репликация

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Web Browser]
    end

    subgraph "Application Layer"
        API[pymongo-api<br/>Flask Application]
    end

    subgraph "MongoDB Sharded Cluster with Replication"
        mongos[mongos<br/>Query Router]
        
        subgraph "Config Servers Replica Set"
            configSrv1[configSrv1<br/>Config Primary]
            configSrv2[configSrv2<br/>Config Secondary]
            configSrv3[configSrv3<br/>Config Secondary]
        end
        
        subgraph "Shard 1 Replica Set"
            shard1_1[shard1-1<br/>Primary]
            shard1_2[shard1-2<br/>Secondary]
            shard1_3[shard1-3<br/>Secondary]
        end
        
        subgraph "Shard 2 Replica Set"
            shard2_1[shard2-1<br/>Primary]
            shard2_2[shard2-2<br/>Secondary]
            shard2_3[shard2-3<br/>Secondary]
        end
    end

    Client -->|HTTP| API
    API -->|MongoDB Protocol| mongos
    
    mongos -->|Metadata| configSrv1
    mongos -->|Metadata| configSrv2
    mongos -->|Metadata| configSrv3
    
    configSrv1 -.->|Replication| configSrv2
    configSrv1 -.->|Replication| configSrv3
    
    mongos -->|Read/Write| shard1_1
    mongos -->|Read| shard1_2
    mongos -->|Read| shard1_3
    
    shard1_1 -.->|Replication| shard1_2
    shard1_1 -.->|Replication| shard1_3
    
    mongos -->|Read/Write| shard2_1
    mongos -->|Read| shard2_2
    mongos -->|Read| shard2_3
    
    shard2_1 -.->|Replication| shard2_2
    shard2_1 -.->|Replication| shard2_3

    style API fill:#4CAF50
    style mongos fill:#FF9800
    style configSrv1 fill:#2196F3
    style configSrv2 fill:#2196F3
    style configSrv3 fill:#2196F3
    style shard1_1 fill:#9C27B0
    style shard1_2 fill:#9C27B0
    style shard1_3 fill:#9C27B0
    style shard2_1 fill:#E91E63
    style shard2_2 fill:#E91E63
    style shard2_3 fill:#E91E63
```

### Компоненты:
- **Config Servers Replica Set**: configSrv1 (Primary), configSrv2, configSrv3 (Secondaries)
- **Shard 1 Replica Set**: shard1-1 (Primary), shard1-2, shard1-3 (Secondaries)
- **Shard 2 Replica Set**: shard2-1 (Primary), shard2-2, shard2-3 (Secondaries)

### Репликация:
- Пунктирные стрелки показывают репликацию данных от Primary к Secondary нодам
- Primary ноды обрабатывают запись (Write)
- Secondary ноды могут обрабатывать чтение (Read)
- При падении Primary автоматически выбирается новая из Secondary (Failover)

---

## Схема 3: Шардирование + Репликация + Кеширование

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Web Browser]
    end

    subgraph "Application Layer"
        API[pymongo-api<br/>Flask Application]
    end

    subgraph "Caching Layer"
        Redis[redis<br/>Redis Cache]
    end

    subgraph "MongoDB Sharded Cluster with Replication"
        mongos[mongos<br/>Query Router]
        
        subgraph "Config Servers Replica Set"
            configSrv1[configSrv1<br/>Config Primary]
            configSrv2[configSrv2<br/>Config Secondary]
            configSrv3[configSrv3<br/>Config Secondary]
        end
        
        subgraph "Shard 1 Replica Set"
            shard1_1[shard1-1<br/>Primary]
            shard1_2[shard1-2<br/>Secondary]
            shard1_3[shard1-3<br/>Secondary]
        end
        
        subgraph "Shard 2 Replica Set"
            shard2_1[shard2-1<br/>Primary]
            shard2_2[shard2-2<br/>Secondary]
            shard2_3[shard2-3<br/>Secondary]
        end
    end

    Client -->|HTTP| API
    API -->|Cache Check| Redis
    API -->|MongoDB Protocol| mongos
    
    mongos -->|Metadata| configSrv1
    mongos -->|Metadata| configSrv2
    mongos -->|Metadata| configSrv3
    
    configSrv1 -.->|Replication| configSrv2
    configSrv1 -.->|Replication| configSrv3
    
    mongos -->|Read/Write| shard1_1
    mongos -->|Read| shard1_2
    mongos -->|Read| shard1_3
    
    shard1_1 -.->|Replication| shard1_2
    shard1_1 -.->|Replication| shard1_3
    
    mongos -->|Read/Write| shard2_1
    mongos -->|Read| shard2_2
    mongos -->|Read| shard2_3
    
    shard2_1 -.->|Replication| shard2_2
    shard2_1 -.->|Replication| shard2_3

    style API fill:#4CAF50
    style Redis fill:#DC382D
    style mongos fill:#FF9800
    style configSrv1 fill:#2196F3
    style configSrv2 fill:#2196F3
    style configSrv3 fill:#2196F3
    style shard1_1 fill:#9C27B0
    style shard1_2 fill:#9C27B0
    style shard1_3 fill:#9C27B0
    style shard2_1 fill:#E91E63
    style shard2_2 fill:#E91E63
    style shard2_3 fill:#E91E63
```

### Новый компонент:
- **redis** - Redis Cache для кеширования частых запросов

### Кеширование:
- Приложение сначала проверяет наличие данных в Redis
- При cache hit - данные возвращаются из Redis (быстрее)
- При cache miss - данные запрашиваются из MongoDB и сохраняются в Redis
- Снижение нагрузки на MongoDB и ускорение ответов

---

## Преимущества итоговой архитектуры

### 1. Горизонтальная масштабируемость (Sharding)
- Данные распределены между несколькими шардами
- Возможность добавления новых шардов при росте нагрузки
- Параллельная обработка запросов на разных шардах

### 2. Отказоустойчивость (Replication)
- Каждый компонент имеет реплики
- Автоматическое восстановление при отказе (Automatic Failover)
- Нулевое время простоя при падении одной ноды

### 3. Производительность (Caching)
- Redis кеширует частые запросы
- Снижение latency для популярных данных
- Уменьшение нагрузки на MongoDB

### 4. Готовность к "черной пятнице"
- Способность обрабатывать высокий трафик
- Отсутствие single point of failure
- Быстрые ответы даже при пиковой нагрузке

