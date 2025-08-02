#!/bin/bash
set -e

function wait_for_mongo() {
  echo "Waiting for $1 ..."
  until mongosh --host "$1" --eval "db.adminCommand('ping')" | grep 'ok' > /dev/null 2>&1; do
    sleep 2
  done
  echo "$1 is available"
}

wait_for_mongo configSrv1:27017
wait_for_mongo configSrv2:27017
wait_for_mongo configSrv3:27017

echo "Initializing config server replica set..."
mongosh --host configSrv1:27017 /scripts/init-config.js

wait_for_mongo shard1a:27018
echo "Initializing shard1 replica set..."
mongosh --host shard1a:27018 /scripts/init-shard1.js

wait_for_mongo shard2a:27019
echo "Initializing shard2 replica set..."
mongosh --host shard2a:27019 /scripts/init-shard2.js

wait_for_mongo mongos_router:27020
echo "Adding shards via mongos router..."
mongosh --host mongos_router:27020 /scripts/init-router.js

echo "Seeding sample data..."

mongosh --host mongos_router:27020 --eval '
  const db = db.getSiblingDB("somedb");
  const docs = [];
  for (let i = 0; i < 1000; i++) {
    docs.push({ age: i, name: "ly" + i });
  }
  db.helloDoc.insertMany(docs);
'

echo "Data inserted."

echo "Shard1 document count:"
mongosh --host shard1a:27018 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard1 contains: " + db.helloDoc.countDocuments() + " docs");
'

echo "Shard2 document count:"
mongosh --host shard2a:27019 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard2 contains: " + db.helloDoc.countDocuments() + " docs");
'

echo ""
echo "Replica Set Roles:"
echo "---------------------"

REPLICAS=(
  "config_server configSrv1:27017"
  "shard1 shard1a:27018"
  "shard2 shard2a:27019"
)

for entry in "${REPLICAS[@]}"; do
  RS_NAME=$(echo "$entry" | awk '{print $1}')
  HOST=$(echo "$entry" | awk '{print $2}')

  echo "Replica Set: $RS_NAME ($HOST)"
  mongosh --host "$HOST" --quiet --eval '
    try {
      const status = rs.status();
      status.members.forEach(m => {
        const role = (m.stateStr === "PRIMARY" || m.stateStr === "SECONDARY" || m.stateStr === "ARBITER") ? m.stateStr : ("❌ " + m.stateStr);
        print(" - " + m.name + "  ➤  " + role);
      });
    } catch (e) {
      print("Error: " + e.message);
    }
  '
  echo ""
done

echo "Done"
