# Шардирование

## 1. Запуск compose.yaml

[compose.yaml](./compose.yaml)

```
docker compose -f compose.yaml up -d
```

## 2. Инициализация кластера скриптом

[mongo-sharding-repl.sh](./scripts/mongo-sharding-repl.sh)

```bash
./scripts/mongo-sharding-repl.sh
```

## 2. Инициализация кластера вручную

### 2.1. Инициализация сервера конфигураций

Подключаемся к поду сервера:
```bash
docker exec -it configSrv mongosh --port 27017
```

Выполняем команду инициализации:
```bash
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
exit();
```

### 2.2. Инициализация шардов

Подключаемся к поду shard1:
```bash
docker exec -it shard1_1 mongosh --port 27011
```

Выполняем команду инициализации:
```bash
rs.initiate(
  {
    _id : "shard1",
    members: [
      { _id: 0, host: "shard1_1:27011" },
      { _id: 1, host: "shard1_2:27012" },
      { _id: 2, host: "shard1_3:27013" }
    ]
  }
);
exit();
```

Подключаемся к поду shard2:
```bash
docker exec -it shard2_1 mongosh --port 27021
```

Выполняем команду инициализации:
```bash
rs.initiate(
  {
    _id : "shard2",
    members: [
      { _id: 0, host: "shard2_1:27021" },
      { _id: 1, host: "shard2_2:27022" },
      { _id: 2, host: "shard2_3:27023" }
    ]
  }
);
exit();
```

### 2.3. Инициализация роутера

Подключаемся к поду роутера:
```bash
docker exec -it mongos_router mongosh --port 27020
```

Выполняем команду добавления шардов и добавления коллекций:
```bash
sh.addShard( "shard1/shard1:27018");
sh.addShard( "shard2/shard2:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

exit();
```

# 3. Тестирование

[Скрипт наполнения тестовыми данными](./scripts/mongo-init.sh)

Результат выполнения:
```bash
------
   The server generated these startup warnings when booting
   2025-11-04T06:10:03.681+00:00: Access control is not enabled for the database. Read and write access to data and configuration is unrestricted
------

[direct: mongos] test> switched to db somedb
[direct: mongos] somedb> {
  acknowledged: true,
  insertedId: ObjectId('690998ec482bbaab234f8fcd')
}
```

[Скрипт тестирования shard1](./scripts/mongo-shard1.sh)
[Скрипт тестирования shard2](./scripts/mongo-shard2.sh)

```bash
saygindenis@MacBook-Air-Denis mongo-sharding-repl % ./scripts/mongo-shard1.sh 
Shard1 (MASTER)
shard1 [direct: primary] test> switched to db somedb
shard1 [direct: primary] somedb> 1016
shard1 [direct: primary] somedb> Shard1 (REPLICA1)
shard1 [direct: secondary] test> switched to db somedb
shard1 [direct: secondary] somedb> 1016
shard1 [direct: secondary] somedb> Shard1 (REPLICA2)
shard1 [direct: secondary] test> switched to db somedb
shard1 [direct: secondary] somedb> 1016
shard1 [direct: secondary] somedb> %   
```

```bash
saygindenis@MacBook-Air-Denis mongo-sharding-repl % ./scripts/mongo-shard2.sh
Shard2 (MASTER)
shard2 [direct: secondary] test> switched to db somedb
shard2 [direct: secondary] somedb> 984
shard2 [direct: secondary] somedb> Shard2 (REPLICA1)
shard2 [direct: secondary] test> switched to db somedb
shard2 [direct: secondary] somedb> 984
shard2 [direct: secondary] somedb> Shard2 (REPLICA2)
shard2 [direct: primary] test> switched to db somedb
shard2 [direct: primary] somedb> 984
shard2 [direct: primary] somedb> %   
```

# 4. Удаление ресурсов

```bash
docker compose -f compose.yaml down -v
```