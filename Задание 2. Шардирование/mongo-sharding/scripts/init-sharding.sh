#!/bin/bash

set -e

echo "Starting MongoDB sharding initialization..."

#!/bin/bash

echo "Adding shards to cluster..."

until mongosh --host mongos_router:27020 --eval "sh.addShard('shard1/shard1:27018')"; do
  echo "Waiting for mongos to be ready..."
  sleep 5
done

until mongosh --host mongos_router:27020 --eval "sh.addShard('shard2/shard2:27019')"; do
  echo "Waiting for shard2 to be ready..."
  sleep 5
done

echo "Shards added successfully!"
echo "Sharding status:"
mongosh --host mongos_router:27020 --eval "sh.status()"

# Добавляем шарды к mongos
echo "Adding shards to mongos..."
mongosh --host mongos_router --port 27020 << 'EOF'


// Создаем базу и включаем шардирование
try {
    sh.enableSharding("somedb");
    print("✓ Sharding enabled for database 'somedb'");
} catch (e) {
    print("ℹ Sharding already enabled or error: " + e);
}

// Создаем коллекцию и шардируем
db = db.getSiblingDB("somedb");

try {
    db.createCollection("helloDoc");
    print("✓ Collection 'helloDoc' created");
} catch (e) {
    print("ℹ Collection already exists or error: " + e);
}

try {
    sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
    print("✓ Collection sharded successfully");
} catch (e) {
    print("ℹ Collection already sharded or error: " + e);
}

// Добавляем тестовые данные только если коллекция пустая
var count = db.helloDoc.countDocuments();
if (count === 0) {
    print("Inserting test data...");
    for(var i = 0; i < 1000; i++) {
        db.helloDoc.insertOne({age: i, name: "user" + i});
    }
    print("✓ Test data inserted (1000 documents)");
} else {
    print("✓ Data already exists (" + count + " documents)");
}

print("Final statistics:");
print("Total documents: " + db.helloDoc.countDocuments());
db.helloDoc.getShardDistribution();
EOF

echo "✓ MongoDB sharding initialization completed successfully!"