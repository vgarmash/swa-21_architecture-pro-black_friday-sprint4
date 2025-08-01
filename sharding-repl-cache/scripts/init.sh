#!/bin/bash

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

docker compose exec -T shard11 mongosh --port 27018 <<EOF

rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 1, host : "shard11:27018" },
        { _id : 2, host : "shard12:27018" },
        { _id : 3, host : "shard13:27018" },
      ]
    }
);
EOF

docker compose exec -T shard21 mongosh --port 27019 <<EOF

rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 1, host : "shard21:27019" },
        { _id : 2, host : "shard22:27019" },
        { _id : 3, host : "shard23:27019" },
      ]
    }
);
EOF

echo "Инициализация реплик..."
sleep 10

docker compose exec -T mongos_router mongosh --port 27020 <<EOF

sh.addShard("shard1/shard11:27018");
sh.addShard("shard1/shard12:27018");
sh.addShard("shard1/shard13:27018");
sh.addShard("shard2/shard21:27019");
sh.addShard("shard2/shard22:27019");
sh.addShard("shard2/shard23:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )

EOF
