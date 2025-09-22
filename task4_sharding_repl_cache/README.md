# task4_sharding_repl_cache

Шардирование + репликация + Redis cache.

## Как запустить
```bash
cd task4_sharding_repl_cache
docker compose up -d
```

## Инициализация и проверка
```bash
bash scripts/init_repl_cluster.sh
bash scripts/seed_data.sh
bash scripts/show_cache_stats.sh
```
Проверьте:
- http://localhost:8082 — `cache_enabled: true`, Sharded, ≥1000 документов.
- Два вызова `http://localhost:8082/helloDoc/users`: первый медленнее, второй должен быть <100мс. 