#!/bin/sh

echo "Waiting for Redis nodes to be ready..."
sleep 30

echo "Checking Redis nodes connectivity..."
for i in 1 2 3 4 5 6; do
  if redis-cli -h redis-node-$i ping | grep -q PONG; then
    echo "Redis node $i is ready"
  else
    echo "Redis node $i is not ready"
    exit 1
  fi
done

echo "Resetting Redis nodes..."
for i in 1 2 3 4 5 6; do
  echo "Resetting node $i"
  redis-cli -h redis-node-$i cluster reset hard
  redis-cli -h redis-node-$i flushall
done

echo "Waiting for reset to complete..."
sleep 5

echo "Initializing Redis cluster..."
redis-cli --cluster create \
  redis-node-1:6379 \
  redis-node-2:6379 \
  redis-node-3:6379 \
  redis-node-4:6379 \
  redis-node-5:6379 \
  redis-node-6:6379 \
  --cluster-replicas 1 \
  --cluster-yes

echo "Checking cluster status..."
redis-cli -h redis-node-1 cluster nodes

echo "Redis cluster initialized successfully!"