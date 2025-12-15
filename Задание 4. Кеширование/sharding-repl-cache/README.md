# pymongo-api

## Как запустить

### Запуск всего кластера
docker compose up -d

### Просмотр логов
docker compose logs -f

### Остановка
docker compose down

### Остановка с удалением данных
docker compose down -v

## Для проверки состояния кластера Mongo

### Проверить статус шардинга
docker compose exec mongos_router mongosh --port 27020 --eval "sh.status()"

### Проверить replica sets
docker compose exec configSrv1 mongosh --port 27017 --eval "rs.status()"
docker compose exec shard1a mongosh --port 27018 --eval "rs.status()"


## Как проверить pymongo-api

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs