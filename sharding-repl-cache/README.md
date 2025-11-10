# Шардирование

## 1. Запуск compose.yaml

[compose.yaml](./compose.yaml)

```
docker compose -f compose.yaml up -d
```

## 2. Инициализация кластера MongoDB

[sharding-repl-cache.sh](./scripts/sharding-repl-cache.sh)

```bash
./scripts/sharding-repl-cache.sh
```

# 3. Тестирование кэширования

Для тестирования нужно выполнить:

```bash
time curl -s http://localhost:8080/test/users > /dev/null
time curl -s http://localhost:8080/test/users > /dev/null
time curl -s http://localhost:8080/test/users > /dev/null
time curl -s http://localhost:8080/test/users > /dev/null
```

Ответ на запрос:
```bash
saygindenis@MacBook-Air-Denis sharding-repl-cache % time curl -s http://localhost:8080/test/users > /dev/null
curl -s http://localhost:8080/test/users > /dev/null  0.00s user 0.01s system 1% cpu 1.074 total
saygindenis@MacBook-Air-Denis sharding-repl-cache % time curl -s http://localhost:8080/test/users > /dev/null
curl -s http://localhost:8080/test/users > /dev/null  0.00s user 0.01s system 40% cpu 0.024 total
saygindenis@MacBook-Air-Denis sharding-repl-cache % time curl -s http://localhost:8080/test/users > /dev/null
curl -s http://localhost:8080/test/users > /dev/null  0.00s user 0.00s system 49% cpu 0.019 total
saygindenis@MacBook-Air-Denis sharding-repl-cache % time curl -s http://localhost:8080/test/users > /dev/null
curl -s http://localhost:8080/test/users > /dev/null  0.01s user 0.00s system 57% cpu 0.018 total
```

# 4. Удаление ресурсов

```bash
docker compose -f compose.yaml down -v
```