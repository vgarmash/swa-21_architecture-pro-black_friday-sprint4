#!/bin/bash

set -e

echo "Starting initialization"

echo "Initializing config server"

docker compose exec -T config-server mongosh --port 27017 <<EOF
    rs.initiate(
        {
            _id: "config-server",
            configsvr: true,
            members: [
                { _id: 0, host: "config-server:27017" }
            ]
        }
    );
EOF

echo "Config server initialized"

echo "Initializing shards"

echo "Initializing shard-1"

docker compose exec -T shard-1 mongosh --port 27018 <<EOF
    rs.initiate(
        {
            _id: "shard-1",
            members: [
                { _id: 0, host: "shard-1:27018" },
            ]
        }
    );
EOF

echo "shard-1 initialized"

echo "Initializing shard-2"

docker compose exec -T shard-2 mongosh --port 27019 <<EOF
    rs.initiate(
        {
            _id: "shard-2",
            members: [
            { _id: 1, host: "shard-2:27019" }
            ]
        }
    );
EOF

echo "shard-2 initialized"

echo "Shards initialized"

echo "Waiting for shards to be ready"

sleep 2

echo "Initializing router"

docker compose exec -T mongos-router mongosh --port 27020 <<EOF
sh.addShard( "shard-1/shard-1:27018");
sh.addShard( "shard-2/shard-2:27019");

sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } );

use somedb;

for(var i = 0; i < 1000; i++) db.helloDoc.insert({age:i, name:"ly"+i});
EOF

echo "Router initialized"

echo "Initialization complete"