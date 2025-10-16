#!/bin/bash

set -e

echo "Starting redis initialization"

docker compose exec -T redis-1 sh -lc 'echo "yes" | \
    redis-cli \
    --cluster create redis-1:6379 redis-2:6379 redis-3:6379 redis-4:6379 redis-5:6379 redis-6:6379 \
    --cluster-replicas 1'

echo "Redis initialized"