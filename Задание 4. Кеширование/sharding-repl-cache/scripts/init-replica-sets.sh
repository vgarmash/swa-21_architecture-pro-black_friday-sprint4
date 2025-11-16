#!/bin/bash

set -e

echo "Waiting for all MongoDB instances to be ready..."
sleep 10

# Функция для проверки готовности MongoDB
wait_for_mongo() {
    local host=$1
    local port=$2
    local max_attempts=30
    local attempt=0

    echo "Waiting for $host:$port to be ready..."

    while [ $attempt -lt $max_attempts ]; do
        if mongosh --host $host --port $port --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
            echo "$host:$port is ready"
            return 0
        fi
        echo "Waiting for $host:$port... (attempt $((attempt+1))/$max_attempts)"
        sleep 2
        attempt=$((attempt+1))
    done

    echo "Timeout waiting for $host:$port"
    return 1
}

# Функция для проверки статуса replica set
check_replset_status() {
    local host=$1
    local port=$2
    local max_attempts=10
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if mongosh --host $host --port $port --eval "
            try {
                var status = rs.status();
                if (status.ok === 1) {
                    print('REPLSET_ACTIVE');
                    quit(0);
                }
            } catch (e) {
                if (e.codeName === 'NotYetInitialized' || e.message.includes('no replset config')) {
                    print('REPLSET_NOT_INITIALIZED');
                    quit(0);
                }
                print('ERROR: ' + e.message);
            }
        " 2>/dev/null | grep -q "REPLSET_ACTIVE"; then
            return 0
        elif mongosh --host $host --port $port --eval "
            try {
                var status = rs.status();
            } catch (e) {
                if (e.codeName === 'NotYetInitialized' || e.message.includes('no replset config')) {
                    print('REPLSET_NOT_INITIALIZED');
                    quit(0);
                }
            }
        " 2>/dev/null | grep -q "REPLSET_NOT_INITIALIZED"; then
            return 1
        fi
        echo "Checking replica set status for $host:$port... (attempt $((attempt+1))/$max_attempts)"
        sleep 3
        attempt=$((attempt+1))
    done

    echo "Timeout checking replica set status for $host:$port"
    return 2
}

# Ждем готовности всех серверов
wait_for_mongo configSrv1 27017
wait_for_mongo configSrv2 27017
wait_for_mongo configSrv3 27017
wait_for_mongo shard1a 27018
wait_for_mongo shard1b 27018
wait_for_mongo shard1c 27018
wait_for_mongo shard2a 27019
wait_for_mongo shard2b 27019
wait_for_mongo shard2c 27019

# Инициализируем config сервер (3 реплики)
echo "Initializing config server replica set..."
if check_replset_status configSrv1 27017; then
    echo "Config server replica set already initialized"
else
    echo "Initializing config server replica set..."
    mongosh --host configSrv1 --port 27017 --eval '
    rs.initiate({
        _id: "config_server",
        configsvr: true,
        members: [
            { _id: 0, host: "configSrv1:27017" },
            { _id: 1, host: "configSrv2:27017" },
            { _id: 2, host: "configSrv3:27017" }
        ]
    })
    '
    echo "Waiting for config server replica set to elect primary..."
    sleep 30
fi

# Инициализируем shard1 (3 реплики)
echo "Initializing shard1 replica set..."
if check_replset_status shard1a 27018; then
    echo "Shard1 replica set already initialized"
else
    echo "Initializing shard1 replica set..."
    mongosh --host shard1a --port 27018 --eval '
    rs.initiate({
        _id: "shard1",
        members: [
            { _id: 0, host: "shard1a:27018" },
            { _id: 1, host: "shard1b:27018" },
            { _id: 2, host: "shard1c:27018" }
        ]
    })
    '
    echo "Waiting for shard1 replica set to elect primary..."
    sleep 30
fi

# Инициализируем shard2 (3 реплики)
echo "Initializing shard2 replica set..."
if check_replset_status shard2a 27019; then
    echo "Shard2 replica set already initialized"
else
    echo "Initializing shard2 replica set..."
    mongosh --host shard2a --port 27019 --eval '
    rs.initiate({
        _id: "shard2",
        members: [
            { _id: 0, host: "shard2a:27019" },
            { _id: 1, host: "shard2b:27019" },
            { _id: 2, host: "shard2c:27019" }
        ]
    })
    '
    echo "Waiting for shard2 replica set to elect primary..."
    sleep 30
fi

# Проверяем статус всех replica sets
echo "Checking replica sets status..."
echo "Config servers:"
mongosh --host configSrv1 --port 27017 --eval '
try {
    rs.status().members.forEach(m => print(m.name + ": " + m.stateStr))
} catch (e) {
    print("Error: " + e.message)
}'

echo "Shard1:"
mongosh --host shard1a --port 27018 --eval '
try {
    rs.status().members.forEach(m => print(m.name + ": " + m.stateStr))
} catch (e) {
    print("Error: " + e.message)
}'

echo "Shard2:"
mongosh --host shard2a --port 27019 --eval '
try {
    rs.status().members.forEach(m => print(m.name + ": " + m.stateStr))
} catch (e) {
    print("Error: " + e.message)
}'

# Пытаемся добавить тестовые данные
echo "Adding test data..."
mongosh --host mongos_router --port 27020 <<EOF 2>/dev/null || echo "Mongos not ready yet, test data will be added later"
use somedb

// Создаем коллекцию если не существует
if (!db.getCollectionNames().includes("helloDoc")) {
    db.createCollection("helloDoc");
}

// Включаем шардирование для базы данных если не включено
sh.enableSharding("somedb");

// Включаем шардирование для коллекции если не включено
try {
    sh.shardCollection("somedb.helloDoc", { "name": "hashed" });
} catch (e) {
    // Коллекция уже зашардирована
}

// Добавляем тестовые данные если их нет
if (db.helloDoc.countDocuments() === 0) {
    for(var i = 0; i < 1000; i++) {
        db.helloDoc.insertOne({
            age: i,
            name: "user" + i,
            timestamp: new Date(),
            data: "sample data " + i
        })
    }
    print("Test data added successfully");
} else {
    print("Test data already exists");
}
EOF


echo "Replica sets initialization completed successfully!"