## 1. Запуск проекта

```bash
docker compose up -d --build
docker compose ps
```

---

## 2. Настройка кластера MongoDB

### 2.1. Репликация для config servers
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

### 2.2. Репликация для шардов
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

### 2.3. Добавляем шарды через mongos
```bash
docker compose exec -T mongos1 mongosh --port 27020 --quiet <<'EOF'
sh.addShard("rsShard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard("rsShard2/shard2-1:27019,shard2-2:27019,shard2-3:27019");
EOF
```

### 2.4. Включаем шардирование для базы и коллекции
```bash
docker compose exec -T mongos1 mongosh --port 27020 --quiet <<'EOF'
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { _id: "hashed" });
EOF
```

---

## 3. Засев данных

```bash
docker compose exec -T mongos1 mongosh --port 27020 --quiet <<'EOF'
db = db.getSiblingDB("somedb");
for (let i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly" + i });
}
print("Total docs:", db.helloDoc.countDocuments());
EOF
```

---

## 4. Redis Cluster

```bash
docker exec -i redis_1 sh -lc 'echo "yes" | redis-cli --cluster create \
  173.17.0.2:6379 173.17.0.3:6379 173.17.0.4:6379 \
  173.17.0.5:6379 173.17.0.6:6379 173.17.0.7:6379 \
  --cluster-replicas 1'
docker exec -it redis_1 redis-cli cluster nodes
```

Ожидаем 6 узлов: 3 master, 3 slave.

---

## 5. Проверка приложения

### 5.1. Корневой эндпоинт
```bash
curl -s http://localhost:8080 | jq .
```

### 5.2. Количество документов
```bash
curl -s http://localhost:8080/helloDoc/count | jq .
```

Ожидается `items_count: 1000`.

### 5.3. Тест кэша
```bash
curl -o /dev/null -s -w 'first_total_ms=%{time_total}\n' http://localhost:8080/helloDoc/users
curl -o /dev/null -s -w 'second_total_ms=%{time_total}\n' http://localhost:8080/helloDoc/users
```

Второй вызов существеннее быстрее первого!
