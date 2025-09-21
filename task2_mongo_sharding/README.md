# task2_mongo_sharding

Шардирование MongoDB (2 шарда) + приложение `pymongo-api`.

## Запуск
```bash
cd task2_mongo_sharding
docker compose up -d
```

## Инициализация и проверка
```bash
bash scripts/init_cluster.sh
bash scripts/seed_data.sh
bash scripts/show_stats.sh
```
Если после инициализации страница http://localhost:8080 возвращает 500, выполните:
```bash
docker compose restart webapi
```

## One-liner (по шагам подряд)
```bash
cd task2_mongo_sharding && docker compose up -d && bash scripts/init_cluster.sh && bash scripts/seed_data.sh && bash scripts/show_stats.sh && docker compose restart webapi
``` 