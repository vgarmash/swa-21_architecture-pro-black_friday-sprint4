docker exec -i shard1 mongosh --host localhost:27018 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard1 has " + db.helloDoc.countDocuments());
'
docker exec -i shard2 mongosh --host localhost:27019 --eval '
  const db = db.getSiblingDB("somedb");
  print("shard2 has " + db.helloDoc.countDocuments());
'
