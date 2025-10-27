#!/bin/bash

# Script to test Redis caching performance
# Tests the /helloDoc/users endpoint with and without cache

echo "================================================"
echo "    Redis Caching Performance Test"
echo "================================================"
echo ""

# Check if API is running
if ! curl -s http://127.0.0.1:8080 > /dev/null 2>&1; then
    echo "❌ Error: API is not running on http://127.0.0.1:8080"
    echo "Please run: docker compose up -d"
    exit 1
fi

# Check if Redis is enabled
CACHE_ENABLED=$(curl -s http://127.0.0.1:8080 | jq -r '.cache_enabled')
if [ "$CACHE_ENABLED" != "true" ]; then
    echo "❌ Error: Redis caching is not enabled"
    echo "Expected: cache_enabled = true"
    echo "Got: cache_enabled = $CACHE_ENABLED"
    exit 1
fi

echo "✅ API is running and Redis is enabled"
echo ""

# Clear cache for clean test
echo "🧹 Clearing Redis cache for clean test..."
docker compose exec -T redis redis-cli FLUSHALL > /dev/null 2>&1
echo ""

# Test 1: First request (without cache)
echo "================================================"
echo "Test 1: First request (WITHOUT cache)"
echo "================================================"
echo "Expected time: ~1.0-1.2 seconds (slow)"
echo ""
echo "Running..."
START_TIME=$(date +%s%N)
RESULT1=$(curl -s http://127.0.0.1:8080/helloDoc/users | jq -r '.users | length')
END_TIME=$(date +%s%N)
TIME1=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000000" | bc)

echo "✅ Documents fetched: $RESULT1"
echo "⏱️  Time taken: ${TIME1}s"
echo ""

# Small delay
sleep 1

# Test 2: Second request (from cache)
echo "================================================"
echo "Test 2: Second request (FROM cache)"
echo "================================================"
echo "Expected time: <0.1 seconds (fast)"
echo ""
echo "Running..."
START_TIME=$(date +%s%N)
RESULT2=$(curl -s http://127.0.0.1:8080/helloDoc/users | jq -r '.users | length')
END_TIME=$(date +%s%N)
TIME2=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000000" | bc)

echo "✅ Documents fetched: $RESULT2"
echo "⏱️  Time taken: ${TIME2}s"
echo ""

# Test 3: Third request (from cache)
echo "================================================"
echo "Test 3: Third request (FROM cache)"
echo "================================================"
echo "Expected time: <0.1 seconds (fast)"
echo ""
echo "Running..."
START_TIME=$(date +%s%N)
RESULT3=$(curl -s http://127.0.0.1:8080/helloDoc/users | jq -r '.users | length')
END_TIME=$(date +%s%N)
TIME3=$(echo "scale=3; ($END_TIME - $START_TIME) / 1000000000" | bc)

echo "✅ Documents fetched: $RESULT3"
echo "⏱️  Time taken: ${TIME3}s"
echo ""

# Calculate speedup
SPEEDUP=$(echo "scale=1; $TIME1 / $TIME2" | bc)

# Results summary
echo "================================================"
echo "                   SUMMARY"
echo "================================================"
echo ""
echo "Request 1 (no cache):  ${TIME1}s"
echo "Request 2 (cached):    ${TIME2}s"
echo "Request 3 (cached):    ${TIME3}s"
echo ""
echo "🚀 Speedup: ${SPEEDUP}x faster with cache!"
echo ""

# Check if caching requirements are met
THRESHOLD=0.1
MEETS_REQUIREMENT=$(echo "$TIME2 < $THRESHOLD" | bc)

if [ "$MEETS_REQUIREMENT" -eq 1 ]; then
    echo "✅ PASSED: Cached requests are < 100ms"
    echo "   Requirement: < ${THRESHOLD}s"
    echo "   Actual: ${TIME2}s"
else
    echo "⚠️  WARNING: Cached requests are >= 100ms"
    echo "   Requirement: < ${THRESHOLD}s"
    echo "   Actual: ${TIME2}s"
fi
echo ""

# Redis stats
echo "================================================"
echo "              Redis Statistics"
echo "================================================"
echo ""

# Number of keys
KEYS_COUNT=$(docker compose exec -T redis redis-cli DBSIZE 2>/dev/null | grep -oE '[0-9]+')
echo "📊 Cached keys: $KEYS_COUNT"

# Show keys
echo "🔑 Cache keys:"
docker compose exec -T redis redis-cli KEYS 'api:cache:*' 2>/dev/null | sed 's/^/   /'
echo ""

# Hit/Miss stats (if available)
echo "📈 Cache stats:"
docker compose exec -T redis redis-cli INFO stats 2>/dev/null | grep -E "keyspace_hits|keyspace_misses" | sed 's/^/   /'
echo ""

echo "================================================"
echo "✅ Cache performance test completed!"
echo "================================================"

