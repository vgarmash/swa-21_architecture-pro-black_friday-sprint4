rs.initiate({
  _id: "shard2Repl",
  members: [
    { _id: 0, host: "dc2-shard2a:27019" },
    { _id: 1, host: "dc2-shard2b:27019" },
    { _id: 2, host: "dc2-shard2c:27019" }
  ]
})
