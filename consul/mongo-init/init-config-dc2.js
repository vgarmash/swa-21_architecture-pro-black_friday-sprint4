rs.initiate({
  _id: "configRepl",
  configsvr: true,
  members: [
    { _id: 0, host: "dc2-cfg1:27017" },
    { _id: 1, host: "dc2-cfg2:27017" },
    { _id: 2, host: "dc2-cfg3:27017" }
  ]
})
