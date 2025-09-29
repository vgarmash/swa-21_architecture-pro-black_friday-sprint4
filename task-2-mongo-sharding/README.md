# Задание 2 — Шардирование MongoDB

Кластер  состоит из:

- config server (`configSrv`)
- два шарда (`shard1`, `shard2`)
- роутер (`mongos_router`)
- приложение `api_app`, которое подключается к кластеру через `mongos`

## Запуск кластера

```bash
docker compose up -d --build
docker compose ps
```

Инициализация шардирования

```bash
docker compose exec -T configSrv mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [ { _id: 0, host: "configSrv:27017" } ]
});
EOF

# Shard1
docker compose exec -T shard1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "shard1",
  members: [ { _id: 0, host: "shard1:27018" } ]
});
EOF

# Shard2
docker compose exec -T shard2 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "shard2",
  members: [ { _id: 0, host: "shard2:27019" } ]
});
EOF
```
Подключение шардов
```bash
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<'EOF'
sh.addShard("shard1/shard1:27018");
sh.addShard("shard2/shard2:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF

```