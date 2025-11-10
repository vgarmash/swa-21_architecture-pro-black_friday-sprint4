# pymongo-api

## Диаграмма

[Схема сервиса](./diagrams/task6.png)

## Этапы создания приложения

- [1. Шардирование](./mongo-sharding/README.md)
- [2. Шардирование и репликация](./mongo-sharding-repl/README.md)
- [3. Шардирование и кэширование](./sharding-repl-cache/README.md)

## Как запустить приложение

Запуск приложений:
```bash
docker compose -f ./sharding-repl-cache/compose.yaml up -d
```

Инициализация кластера MongoDB:

```bash
./sharding-repl-cache/scripts/sharding-repl-cache.sh
```

Удаление приложения и ресурсов:
```bash
docker compose -f ./sharding-repl-cache/compose.yaml down -v
```

## Архитектурный документ

[Архитектурный документ](./architect/architect.md)