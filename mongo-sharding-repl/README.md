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

В скрипте включено ожидание 25 секунд после команд инциализации шардов, за это время кластер соединяется и собирается. По окончании скрипта в БД будет загружено 100 документов с примерный output:
```
📍 Shard1 containes:
shard1 [direct: primary] test> switched to db somedb
shard1 [direct: primary] somedb> 492
shard1 [direct: primary] somedb> 📍 Shard2 containes:
shard2 [direct: secondary] test> switched to db somedb
shard2 [direct: secondary] somedb> 508
```

## Как проверить

### Если вы запускаете проект на локальной машине

Откройте в браузере http://localhost:8080

Output:
```
{
  "mongo_topology_type": "Sharded",
  "mongo_replicaset_name": null,
  "mongo_db": "somedb",
  "read_preference": "Primary()",
  "mongo_nodes": [
    [
      "mongos_router1",
      27017],
    [
      "mongos_router2",
      27017],
    [
      "mongos_router3",
      27017]
  ],
  "mongo_primary_host": null,
  "mongo_secondary_hosts": [],
  "mongo_is_primary": true,
  "mongo_is_mongos": true,
  "collections": {
    "helloDoc": {
      "documents_count": 1000
    }
  },
  "shards": {
    "shard1": "shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018",
    "shard2": "shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018"
  },
  "cache_enabled": false,
  "status": "OK"
}
```
### Если вы запускаете проект на предоставленной виртуальной машине

Узнать белый ip виртуальной машины

```shell
curl --silent http://ifconfig.me
```

Откройте в браузере http://<ip виртуальной машины>:8080

## Доступные эндпоинты

Список доступных эндпоинтов, swagger http://<ip виртуальной машины>:8080/docs