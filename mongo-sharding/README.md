# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker-compose up -d
```

Инициализируем и заполняем тестовыми данными

```shell
./scripts/mongo-init.sh
```

## Как проверить

```shell
./scripts/test-shards-count.sh
```