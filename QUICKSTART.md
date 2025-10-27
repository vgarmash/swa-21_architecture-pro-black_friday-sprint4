# ⚡ Быстрый старт

> Запуск и проверка за 5 минут  
> 🏠 [← Вернуться к README](README.md)

## Три простых команды

```bash
# 1. Запуск
docker compose up -d

# 2. Инициализация (подождите 10 сек)
./scripts/init-sharding.sh

# 3. Проверка
curl http://localhost:8080 | jq
```

## Что должно получиться

```json
{
  "mongo_topology_type": "Sharded",          // ✅
  "mongo_is_mongos": true,                   // ✅
  "collections": {
    "helloDoc": {
      "documents_count": 1000                // ✅
    }
  },
  "shards": {
    "shard1ReplSet": "...",                  // ✅
    "shard2ReplSet": "..."                   // ✅
  },
  "shard_distribution": {                    // ✅
    "helloDoc": {
      "shard1ReplSet": { "count": 500 },
      "shard2ReplSet": { "count": 500 }
    }
  },
  "status": "OK"                             // ✅
}
```

## Открыть в браузере

http://localhost:8080

## Если что-то пошло не так

```bash
# Полная перезагрузка
docker compose down -v
docker compose up -d
sleep 10
./scripts/init-sharding.sh
```

## Подробнее

- 🧪 [Полное руководство по проверке](TESTING.md)
- ⚙️ [Подробная настройка](SHARDING_SETUP.md)
- 🏠 [Главная документация](README.md)

