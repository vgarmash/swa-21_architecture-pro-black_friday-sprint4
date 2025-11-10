# Шардирование

## 1. Запуск compose.yaml

[compose.yaml](./compose.yaml)

```
docker compose -f compose.yaml up -d
```

## 2. Инициализация кластера скриптом

[mongo-sharding.sh](./scripts/mongo-sharding.sh)

```bash
./scripts/mongo-sharding.sh
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
```

В ответ получим результат инициализации:
```bash
{
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1761458472, i: 1 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1761458472, i: 1 })
}
```

Выходим из пода:
```bash
exit();
```

### 2.2. Инициализация шардов

Подключаемся к поду shard1:
```bash
docker exec -it shard1 mongosh --port 27018
```

Выполняем команду инициализации:
```bash
rs.initiate(
  {
    _id : "shard1",
    members: [
      { _id : 0, host : "shard1:27018" }
    ]
  }
);
```

В ответ получим результат инициализации:
```bash
{
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1761458495, i: 1 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1761458495, i: 1 })
}
```

Выходим из пода:
```bash
exit();
```

Подключаемся к поду shard2:
```bash
docker exec -it shard2 mongosh --port 27019
```

Выполняем команду инициализации:
```bash
rs.initiate(
  {
    _id : "shard2",
    members: [
      { _id : 1, host : "shard2:27019" }
    ]
  }
);
```

В ответ получим результат инициализации:
```bash
{
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1761458518, i: 1 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1761458518, i: 1 })
}
```

Выходим из пода:
```bash
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
```

Результат выполнения команды:
```bash
{
  shardAdded: 'shard1',
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1761458537, i: 20 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1761458537, i: 20 })
}

{
  shardAdded: 'shard2',
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1761458544, i: 24 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1761458544, i: 18 })
}

{
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1761458549, i: 10 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1761458549, i: 7 })
}

{
  collectionsharded: 'somedb.helloDoc',
  ok: 1,
  '$clusterTime': {
    clusterTime: Timestamp({ t: 1761458556, i: 49 }),
    signature: {
      hash: Binary.createFromBase64('AAAAAAAAAAAAAAAAAAAAAAAAAAA=', 0),
      keyId: Long('0')
    }
  },
  operationTime: Timestamp({ t: 1761458556, i: 48 })
}
```

Выходим из пода:
```bash
exit();
```

# 3. Тестирование

[Скрипт наполнения тестовыми данными](./scripts/mongo-init.sh)

Результат выполнения:
```bash
   The server generated these startup warnings when booting
   2025-10-26T05:29:20.240+00:00: Access control is not enabled for the database. Read and write access to data and configuration is unrestricted
------

[direct: mongos] test> switched to db somedb
[direct: mongos] somedb> {
  acknowledged: true,
  insertedId: ObjectId('68fdb991c9d20dd1e64f8be5')
}
```

[Скрипт тестирования shard1](./scripts/mongo-shard1.sh)
[Скрипт тестирования shard2](./scripts/mongo-shard2.sh)

```bash
saygindenis@MacBook-Air-Denis mongo-sharding % ./scripts/mongo-shard1.sh 
Shard1
shard1 [direct: primary] test> switched to db somedb
shard1 [direct: primary] somedb> 1016
shard1 [direct: primary] somedb> % 
```

```bash
saygindenis@MacBook-Air-Denis mongo-sharding % ./scripts/mongo-shard2.sh
Shard2
shard2 [direct: primary] test> switched to db somedb
shard2 [direct: primary] somedb> 984
shard2 [direct: primary] somedb> %
```

# 4. Удаление ресурсов

```bash
docker compose -f compose.yaml down -v
```