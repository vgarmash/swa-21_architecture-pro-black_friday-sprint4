rs.initiate({
  _id: "shard1Repl",
  members: [
    { _id: 0, host: "dc2-shard1a:27018" },
    { _id: 1, host: "dc2-shard1b:27018" },
    { _id: 2, host: "dc2-shard1c:27018" }
  ]
})
