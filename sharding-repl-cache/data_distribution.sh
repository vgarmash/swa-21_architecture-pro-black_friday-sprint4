docker exec -i shard1a mongosh --host shard1a:27018 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard1a has " + db.helloDoc.countDocuments());
'
docker exec -i shard1b mongosh --host shard1b:27018 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard1b has " + db.helloDoc.countDocuments());
'
docker exec -i shard1c mongosh --host shard1c:27018 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard1c has " + db.helloDoc.countDocuments());
'
docker exec -i shard2a mongosh --host shard2a:27019 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard2a has " + db.helloDoc.countDocuments());
'
docker exec -i shard2b mongosh --host shard2b:27019 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard2b has " + db.helloDoc.countDocuments());
'
docker exec -i shard2c mongosh --host shard2c:27019 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard2c has " + db.helloDoc.countDocuments());
'
