#!/bin/bash

###
# Инициализация кластера
###

# Инициализация сервера конфигураций
echo '==== Инициализация сервера конфигураций ===='
docker compose exec -T configSrv mongosh --port 27017 <<EOF
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "configSrv:27017" }
    ]
  }
);
EOF

# Инициализация шардов
echo '==== Инициализация шарда 1 ===='
docker compose exec -T shard1_1 mongosh --port 27011 <<EOF
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
EOF

echo '==== Инициализация шарда 2 ===='
docker compose exec -T shard2_1 mongosh --port 27021 <<EOF
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
EOF

# Инициализация роутера
echo '==== Инициализация роутера ===='
docker compose exec -T mongos_router mongosh --port 27020 <<EOF
sh.addShard( "shard1/shard1_1:27011");
sh.addShard( "shard2/shard2_1:27021");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
EOF
