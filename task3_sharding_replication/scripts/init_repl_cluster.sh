#!/usr/bin/env bash
set -euo pipefail

# Init config RS
cat <<'EOF' | docker compose exec -T cfgnode mongosh --quiet --port 27017
try{rs.initiate({_id:"cfgAlpha",configsvr:true,members:[{_id:0,host:"cfgnode:27017"}]})}catch(e){print(e)}
EOF

# Init rsA (3 members)
cat <<'EOF' | docker compose exec -T shard_a1 mongosh --quiet --port 27018
try{rs.initiate({_id:"rsA",members:[{_id:0,host:"shard_a1:27018"},{_id:1,host:"shard_a2:27018"},{_id:2,host:"shard_a3:27018"}]})}catch(e){print(e)}
EOF

# Init rsB (3 members)
cat <<'EOF' | docker compose exec -T shard_b1 mongosh --quiet --port 27019
try{rs.initiate({_id:"rsB",members:[{_id:0,host:"shard_b1:27019"},{_id:1,host:"shard_b2:27019"},{_id:2,host:"shard_b3:27019"}]})}catch(e){print(e)}
EOF

# Configure mongos
cat <<'EOF' | docker compose exec -T router mongosh --quiet --port 27017
try{sh.addShard("rsA/shard_a1:27018,shard_a2:27018,shard_a3:27018")}catch(e){print(e)}
try{sh.addShard("rsB/shard_b1:27019,shard_b2:27019,shard_b3:27019")}catch(e){print(e)}
try{sh.enableSharding("somedb")}catch(e){print(e)}
try{sh.shardCollection("somedb.helloDoc",{_id:"hashed"})}catch(e){print(e)}
sh.status()
EOF

# Restart services
docker compose restart router webapi

echo "Replica cluster initialized" 