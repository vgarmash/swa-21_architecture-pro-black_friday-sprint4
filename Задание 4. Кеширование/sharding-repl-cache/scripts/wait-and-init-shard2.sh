#!/bin/bash

echo "Waiting for shard2 servers to be ready..."
until mongosh --host shard2a:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for shard2a..."
  sleep 2
done

until mongosh --host shard2b:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for shard2b..."
  sleep 2
done

until mongosh --host shard2c:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for shard2c..."
  sleep 2
done

echo "Initializing shard2 replica set..."
mongosh --host shard2a:27017 --eval "
try {
  rs.initiate({
    _id: 'shard2rs',
    members: [
      {_id: 0, host: 'shard2a:27017', priority: 2},
      {_id: 1, host: 'shard2b:27017', priority: 1},
      {_id: 2, host: 'shard2c:27017', priority: 1}
    ]
  })
  print('✓ Shard2 replica set initiated');
} catch (e) {
  if (e.codeName === 'AlreadyInitialized') {
    print('ℹ Shard2 already initialized, reconfiguring...');
    cfg = rs.conf();
    cfg.members = [
      {_id: 0, host: 'shard2a:27017', priority: 2},
      {_id: 1, host: 'shard2b:27017', priority: 1},
      {_id: 2, host: 'shard2c:27017', priority: 1}
    ];
    rs.reconfig(cfg, {force: true});
  } else {
    throw e;
  }
}
"

echo "Waiting for shard2 primary election..."
sleep 10

# Проверяем, что есть primary
echo "Checking for shard2 primary..."
mongosh --host shard2a:27017 --eval "
var status = rs.status();
var primary = status.members.find(m => m.state === 1);
if (primary) {
  print('✓ Shard2 primary elected: ' + primary.name);
} else {
  print('❌ Shard2 no primary found! Current status:');
  printjson(status);
}
"

echo "Shard2 replica set initialized!"