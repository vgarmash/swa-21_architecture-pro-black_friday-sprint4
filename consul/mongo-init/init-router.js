sh.addShard("shard1Repl/dc1-shard1a:27018")
sh.addShard("shard2Repl/dc1-shard2a:27019")

sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { name: "hashed" })
