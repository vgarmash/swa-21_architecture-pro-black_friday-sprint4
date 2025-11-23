#!/bin/bash

echo "Waiting for config servers to be ready..."
until mongosh --host configSrv1:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for configSrv1..."
  sleep 2
done

until mongosh --host configSrv2:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for configSrv2..."
  sleep 2
done

until mongosh --host configSrv3:27017 --eval "db.adminCommand('ismaster')" | grep -q "ismaster"; do
  echo "Waiting for configSrv3..."
  sleep 2
done

echo "Initializing config replica set..."
mongosh --host configSrv1:27017 --eval "
try {
  rs.initiate({
    _id: 'configrs',
    configsvr: true,
    members: [
      {_id: 0, host: 'configSrv1:27017', priority: 2},
      {_id: 1, host: 'configSrv2:27017', priority: 1},
      {_id: 2, host: 'configSrv3:27017', priority: 1}
    ]
  })
} catch (e) {
  // Если replica set уже инициализирован, принудительно реконфигурируем
  if (e.codeName === 'AlreadyInitialized') {
    print('Replica set already initialized, reconfiguring...');
    cfg = rs.conf();
    cfg.members = [
      {_id: 0, host: 'configSrv1:27017', priority: 2},
      {_id: 1, host: 'configSrv2:27017', priority: 1},
      {_id: 2, host: 'configSrv3:27017', priority: 1}
    ];
    rs.reconfig(cfg, {force: true});
  } else {
    throw e;
  }
}
"

echo "Waiting for primary election..."
sleep 10

# Проверяем, что есть primary
echo "Checking for primary..."
mongosh --host configSrv1:27017 --eval "
var status = rs.status();
var primary = status.members.find(m => m.state === 1);
if (primary) {
  print('✓ Primary elected: ' + primary.name);
} else {
  print('❌ No primary found! Current status:');
  printjson(status);
  throw new Error('No primary in config replica set');
}
"

echo "Config replica set initialized!"