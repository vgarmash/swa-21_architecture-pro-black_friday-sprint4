# pymongo-api

## Как запустить

Запускаем mongodb и приложение

```shell
docker compose up -d
```

Заполняем mongodb данными

```shell
./scripts/mongo-init.sh
```

## Как проверить
1. Откройте http://<ip виртуальной машины>:8080/docs (http://localhost:8080/docs)
2. Вызовите эндпоинт /<collection_name>/users
collection_name = helloDoc
3. Второй вызов должен выполниться значительно быстрее, чем первый

Output pymongo-api:
```
2025-08-24 22:00:42 {"asctime": "2025-08-24 19:00:42,123", "process": 1, "levelname": "INFO", "X-API-REQUEST-ID": "91b0a3af-8b01-4334-be37-a004f07f6388", "request": {"method": "GET", "path": "/helloDoc/users", "ip": "173.17.0.1"}, "response": {"status": "successful", "status_code": 200, "time_taken": "1.0363s"}}
2025-08-24 22:01:22 {"asctime": "2025-08-24 19:01:22,352", "process": 1, "levelname": "INFO", "X-API-REQUEST-ID": "bbee18cb-dde0-4fbf-954a-655b0b8f6634", "request": {"method": "GET", "path": "/helloDoc/users", "ip": "173.17.0.1"}, "response": {"status": "successful", "status_code": 200, "time_taken": "0.0441s"}}
```

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