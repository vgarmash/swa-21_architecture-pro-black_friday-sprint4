#!/bin/bash

###
# Инициализируем бд
###
docker compose exec -T config1 mongosh --port 27019 --quiet <<EOF
rs.initiate(
  {
    _id : "config_server",
       configsvr: true,
    members: [
      { _id : 0, host : "config1:27019" },
      { _id : 1, host : "config2:27019" },
      { _id : 2, host : "config3:27019" }
    ]
  }
);
exit
EOF
echo "✅ config initialized!"

docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1-1:27018" },
        { _id : 1, host : "shard1-2:27018" },
        { _id : 2, host : "shard1-3:27018" }
      ]
    });
exit
EOF
echo "✅ shard1 initialized!"

docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
       { _id : 0, host : "shard2-1:27018" },
       { _id : 1, host : "shard2-2:27018" },
       { _id : 2, host : "shard2-3:27018" }
      ]
    });
exit
EOF
echo "✅ shard2 initialized!"
sleep 25

docker compose exec -T mongos_router1 mongosh --port 27017 --quiet <<EOF 
sh.addShard( "shard1/shard1-1:27018,shard1-2:27018,shard1-3:27018");
sh.addShard( "shard2/shard2-1:27018,shard2-2:27018,shard2-3:27018");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });
use somedb;
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i});
db.helloDoc.countDocuments();
exit
EOF

echo "✅ Data Loaded!"
echo "📍 Shard1 containes:"
docker compose exec -T shard1-1 mongosh --port 27018 --quiet <<EOF
use somedb;
db.helloDoc.countDocuments();
exit
EOF

echo "📍 Shard2 containes:"
docker compose exec -T shard2-1 mongosh --port 27018 --quiet <<EOF
use somedb;
db.helloDoc.countDocuments();
exit
EOF
