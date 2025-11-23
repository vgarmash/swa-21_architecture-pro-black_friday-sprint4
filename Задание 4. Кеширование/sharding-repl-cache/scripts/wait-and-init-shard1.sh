#!/bin/bash

echo "Waiting for shard1 servers to be ready..."
until mongosh --host shard1a:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for shard1a..."
  sleep 2
done

until mongosh --host shard1b:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for shard1b..."
  sleep 2
done

until mongosh --host shard1c:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for shard1c..."
  sleep 2
done

echo "Initializing shard1 replica set..."
mongosh --host shard1a:27017 --eval "
try {
  rs.initiate({
    _id: 'shard1rs',
    members: [
      {_id: 0, host: 'shard1a:27017', priority: 2},
      {_id: 1, host: 'shard1b:27017', priority: 1},
      {_id: 2, host: 'shard1c:27017', priority: 1}
    ]
  })
  print('✓ Shard1 replica set initiated');
} catch (e) {
  if (e.codeName === 'AlreadyInitialized') {
    print('ℹ Shard1 already initialized, reconfiguring...');
    cfg = rs.conf();
    cfg.members = [
      {_id: 0, host: 'shard1a:27017', priority: 2},
      {_id: 1, host: 'shard1b:27017', priority: 1},
      {_id: 2, host: 'shard1c:27017', priority: 1}
    ];
    rs.reconfig(cfg, {force: true});
  } else {
    throw e;
  }
}
"

echo "Waiting for shard1 primary election..."
sleep 10

# Проверяем, что есть primary
echo "Checking for shard1 primary..."
mongosh --host shard1a:27017 --eval "
var status = rs.status();
var primary = status.members.find(m => m.state === 1);
if (primary) {
  print('✓ Shard1 primary elected: ' + primary.name);
} else {
  print('❌ Shard1 no primary found! Current status:');
  printjson(status);
}
"

echo "Shard1 replica set initialized!"