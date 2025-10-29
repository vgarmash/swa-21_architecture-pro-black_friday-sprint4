#!/bin/bash

wait_for_primary() {
  local service=$1
  local port=$2
  echo "⏳ Waiting for primary in $service ..."
  until docker compose exec -T "$service" mongosh --port "$port" --quiet --eval \
    'try { 
       const s = db.hello();
       if (s.isWritablePrimary || s.ismaster) { print("true"); } 
     } catch (e) { }' | grep true >/dev/null; do
    sleep 2
  done
  echo "✅ $service has a primary!"
}

# init config_server
docker compose exec -T configSrv mongosh --port 27017 --quiet <<EOF
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

# init shard 1
docker compose exec -T shard1-repl1 mongosh --port 27018 --quiet <<EOF
rs.initiate(
    {
      _id : "shard1",
      members: [
        { _id : 0, host : "shard1-repl1:27018" },
        { _id : 1, host : "shard1-repl2:27021" },
        { _id : 2, host : "shard1-repl3:27022" }
      ]
    }
);
EOF

# init shard 2
docker compose exec -T shard2-repl1 mongosh --port 27019 --quiet <<EOF
rs.initiate(
    {
      _id : "shard2",
      members: [
        { _id : 0, host : "shard2-repl1:27019" },
        { _id : 1, host : "shard2-repl2:27023" },
        { _id : 2, host : "shard2-repl3:27024" }
      ]
    }
  );
EOF

# wait replicas is ready
wait_for_primary shard1-repl1 27018
wait_for_primary shard2-repl1 27019

# init mongos_router
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
sh.addShard("shard1/shard1-repl1:27018,shard1-repl2:27021,shard1-repl3:27022");
sh.addShard("shard2/shard2-repl1:27019,shard2-repl2:27023,shard2-repl3:27024");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
EOF

# generate test data
docker compose exec -T mongos_router mongosh --port 27020 --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
db.helloDoc.countDocuments() 
EOF



