#!/usr/bin/env bash
set -euo pipefail

# Init config RS
cat <<'EOF' | docker compose exec -T cfgnode mongosh --quiet --port 27017
try {
  rs.initiate({_id:"cfgAlpha", configsvr:true, members:[{_id:0, host:"cfgnode:27017"}]})
} catch(e) { print(e) }
EOF

# Init shard RS A
cat <<'EOF' | docker compose exec -T shard_a mongosh --quiet --port 27018
try {
  rs.initiate({_id:"rsA", members:[{_id:0, host:"shard_a:27018"}]})
} catch(e) { print(e) }
EOF

# Init shard RS B
cat <<'EOF' | docker compose exec -T shard_b mongosh --quiet --port 27019
try {
  rs.initiate({_id:"rsB", members:[{_id:0, host:"shard_b:27019"}]})
} catch(e) { print(e) }
EOF

# Configure mongos
cat <<'EOF' | docker compose exec -T router mongosh --quiet --port 27017
try { sh.addShard("rsA/shard_a:27018") } catch(e) { print(e) }
try { sh.addShard("rsB/shard_b:27019") } catch(e) { print(e) }
try { sh.enableSharding("somedb") } catch(e) { print(e) }
try { sh.shardCollection("somedb.helloDoc", { _id: "hashed" }) } catch(e) { print(e) }
sh.status()
EOF

# Restart services to pick up state
docker compose restart router webapi

echo "Cluster initialized and services restarted" 