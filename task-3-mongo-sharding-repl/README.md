## Запуск 

```bash
docker compose up -d --build
docker compose ps
```

## Инициализация 

### Config Server RS
```bash
docker compose exec -T configsvr1 mongosh --port 27017 --quiet <<'EOF'
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [
    { _id: 0, host: "configsvr1:27017" },
    { _id: 1, host: "configsvr2:27017" },
    { _id: 2, host: "configsvr3:27017" }
  ]
});
EOF
```

### Shard 1 RS
```bash
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<'EOF'
rs.initiate({
  _id: "rsShard1",
  members: [
    { _id: 0, host: "shard1-1:27018" },
    { _id: 1, host: "shard1-2:27018" },
    { _id: 2, host: "shard1-3:27018" }
  ]
});
EOF
```

### Shard 2 RS
```bash
docker compose exec -T shard2-1 mongosh --port 27019 --quiet <<'EOF'
rs.initiate({
  _id: "rsShard2",
  members: [
    { _id: 0, host: "shard2-1:27019" },
    { _id: 1, host: "shard2-2:27019" },
    { _id: 2, host: "shard2-3:27019" }
  ]
});
EOF
```

## Подключение шардов и включение шардирования 

### Добавить оба шард-репликасета
```bash
docker compose exec -T mongos1 mongosh --port 27020 --quiet <<'EOF'
sh.addShard("rsShard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("rsShard2/shard2-1:27019,shard2-2:27019,shard2-3:27019");
sh.status();
EOF
```

### Включить шардирование БД и коллекции
```bash
docker compose exec -T mongos1 mongosh --port 27020 --quiet <<'EOF'
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF
```


## Загрузка данных

```bash
docker compose exec -T mongos1 mongosh --port 27020 --quiet <<'EOF'
db = db.getSiblingDB("somedb");
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}
print("Total docs:", db.helloDoc.countDocuments());
EOF
```


## Проверки через HTTP API приложения

### Топология и наличие коллекции
```bash
curl -s http://localhost:8080 | jq .
```

### Общее количество документов
```bash
curl -s http://localhost:8080/helloDoc/count | jq .
```