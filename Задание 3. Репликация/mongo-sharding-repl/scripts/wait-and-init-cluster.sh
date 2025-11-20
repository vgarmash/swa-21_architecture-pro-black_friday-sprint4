#!/bin/bash

echo "Waiting for mongos_router to be ready..."
until mongosh --host mongos_router:27020 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for mongos..."
  sleep 2
done

echo "Adding shards to cluster..."
mongosh --host mongos_router:27020 --eval "
sh.addShard('shard1rs/shard1a:27017,shard1b:27017,shard1c:27017');
sh.addShard('shard2rs/shard2a:27017,shard2b:27017,shard2c:27017');
"

echo "Enabling sharding on test database..."
mongosh --host mongos_router:27020 --eval "
db = db.getSiblingDB('test');
sh.enableSharding('test');
"

echo "Cluster initialization completed!"

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