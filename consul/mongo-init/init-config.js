rs.initiate({
  _id: "configRepl",
  configsvr: true,
  members: [
    { _id: 0, host: "dc1-cfg1:27017" },
    { _id: 1, host: "dc1-cfg2:27017" },
    { _id: 2, host: "dc1-cfg3:27017" }
  ]
})
