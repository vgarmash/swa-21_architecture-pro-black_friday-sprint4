#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/lib/common.sh"

DB_NAME="${DB_NAME:-somedb}"
COLL_NAME="${COLL_NAME:-helloDoc}"
NS="${DB_NAME}.${COLL_NAME}"

KEEP="${KEEP:-0}"
SKIP_DEMO="${SKIP_DEMO:-0}"
VERBOSE="${VERBOSE:-0}"
SKEW_MAX_PCT="${SKEW_MAX_PCT:-60}"
SAMPLE_N="${SAMPLE_N:-8}"
API_BASE="${API_BASE:-http://127.0.0.1:8080}"
API_BASE="${API_BASE%/}"
CACHE_SLA_MS="${CACHE_SLA_MS:-100}"

log "Verify one-shot flow (up → init → demo? → checks → down?)"

log "Stopping previous containers (if any)..."
${COMPOSE} --profile core --profile router --profile demo down 2>/dev/null || true

log "Starting core + router containers..."
${COMPOSE} --profile core --profile router up -d
WAIT_MONGOS=1 bash "$SCRIPT_DIR/init-bootstrap.sh"

# Optional populate
if [[ "${SKIP_DEMO}" == "0" ]]; then
  bash "$SCRIPT_DIR/demo-populate.sh"
fi

# Ensure mongos
wait_ping mongos 27017

log "Starting demo services (redis, api)"
# Start demo services with all profiles to resolve dependencies, but don't recreate existing containers
${COMPOSE} --profile core --profile router --profile demo up -d --no-recreate redis pymongo_api

wait_http_ok "${API_BASE}/docs" 120

# Shards and balancer
log "Shards:"
compose_exec mongos 'mongosh --quiet --eval "db.getSiblingDB(\"admin\").runCommand({listShards:1}).shards.forEach(s=>print(s._id+\" \"+s.host))"'
compose_exec mongos 'mongosh --quiet --eval "print(\"balancer.enabled=\"+sh.getBalancerState())"'
[[ "$VERBOSE" == "1" ]] && compose_exec mongos 'mongosh --quiet --eval "sh.status()"'

# Replica count check
log "Checking replica sets:"
SHARD1_REPLICAS=$(compose_exec shard1-1 "mongosh --port 27018 --quiet --eval \"rs.status().members.length\"" || echo "0")
SHARD2_REPLICAS=$(compose_exec shard2-1 "mongosh --port 27018 --quiet --eval \"rs.status().members.length\"" || echo "0")
log "  shard1ReplSet: ${SHARD1_REPLICAS} replicas"
log "  shard2ReplSet: ${SHARD2_REPLICAS} replicas"
TOTAL_REPLICAS=$((SHARD1_REPLICAS + SHARD2_REPLICAS))
log "  Total replicas: ${TOTAL_REPLICAS}"
[[ "$TOTAL_REPLICAS" -ge 6 ]] || die "Expected at least 6 replicas (3 per shard), found ${TOTAL_REPLICAS}"

# Collection sharded?
compose_exec mongos "mongosh --quiet --eval \"db.getSiblingDB('$DB_NAME').getCollection('$COLL_NAME').stats().sharded?1:0\"" | grep -q '^1$' \
  || die "Collection $NS is not sharded"

# Document count
COUNT=$(compose_exec mongos "mongosh --quiet --eval \"db.getSiblingDB('$DB_NAME').getCollection('$COLL_NAME').countDocuments({})\"")
log "Total documents in $NS: $COUNT"
[[ "$COUNT" =~ ^[0-9]+$ && "$COUNT" -ge 1000 ]] || die "Expected at least 1000 documents in $NS, found $COUNT"

# Chunks skew
log "Chunks per shard (skew ≤ ${SKEW_MAX_PCT}%):"
compose_exec mongos "mongosh --quiet --eval \"
  (function(){
    const ns='$NS', skew=${SKEW_MAX_PCT};
    const arr=db.getSiblingDB('config').chunks.aggregate([
      { \\\$match: { ns: ns } },
      { \\\$group: { _id: '\\\$shard', chunks: { \\\$sum: 1 } } }
    ]).toArray();
    if(arr.length===0){ print('No chunks for '+ns); return; }
    const total=arr.reduce((a,b)=>a+b.chunks,0);
    const avg=total/arr.length;
    let worst=0;
    arr.forEach(e=>{ const pct=avg?Math.abs(e.chunks-avg)/avg*100:0; if(pct>worst){ worst=pct; }});
    print('Chunks: '+arr.map(e=>e._id+':'+e.chunks).join(', '));
    print('Chunks skew% (max): '+worst.toFixed(1));
    if(worst>skew && total>0){ throw new Error('Chunk skew '+worst.toFixed(1)+'% exceeds '+skew+'%'); }
  })();
\""

# Docs skew via collStats
log "Docs per shard via collStats (skew ≤ ${SKEW_MAX_PCT}%):"
compose_exec mongos "mongosh --quiet --eval \"
  (function(){
    const dbName='$DB_NAME', coll='$COLL_NAME', skew=${SKEW_MAX_PCT};
    const st=db.getSiblingDB(dbName).runCommand({collStats: coll, verbose:true});
    if(!st.shards){ print('No per-shard stats (maybe not sharded?)'); return; }
    const entries=Object.entries(st.shards).map(([k,v])=>({shard:k, count:(v.count||v.n||0)}));
    const total=entries.reduce((a,b)=>a+b.count,0);
    const avg=total/entries.length;
    let worst=0;
    entries.forEach(e=>{ const pct=avg?Math.abs(e.count-avg)/avg*100:0; if(pct>worst){ worst=pct; }});
    print('Counts: '+entries.map(e=>e.shard+':'+e.count).join(', '));
    print('Counts skew% (max): '+worst.toFixed(1));
    if(worst>skew && total>0){ throw new Error('Docs skew '+worst.toFixed(1)+'% exceeds '+skew+'%'); }
  })();
\""

# Routing sampling
log "Routing sample by _id (N=${SAMPLE_N}): expect single-shard targeting"
compose_exec mongos "mongosh --quiet --eval \"
  (function(){
    const dbName='$DB_NAME', coll='$COLL_NAME', N=${SAMPLE_N};
    const myDb=db.getSiblingDB(dbName), c=myDb.getCollection(coll);
    if(c.countDocuments({})===0){ print('No docs to sample'); return; }
    const ids=c.aggregate([{ \\\$sample: { size: N } }, { \\\$project: {_id:1} }]).toArray().map(d=>d._id);
    let multi=0;
    function shardsFromExplain(exp){
      if(exp?.queryPlanner?.winningPlan?.shards){
        return exp.queryPlanner.winningPlan.shards.map(s=>s.shardName||s.shard||s);
      }
      if(exp?.queryPlanner?.shards){
        return exp.queryPlanner.shards.map(s=>s.shardName||s.shard||s);
      }
      if(exp?.shards && typeof exp.shards==='object'){
        return Object.keys(exp.shards);
      }
      return [];
    }
    ids.forEach(id=>{
      const exp=myDb.runCommand({ explain: { find: coll, filter: { _id: id } }, verbosity: 'queryPlanner' });
      const shards=shardsFromExplain(exp);
      if(shards.length>1){ multi++; }
    });
    if(multi>0){ throw new Error('Detected '+multi+' broadcast queries on equality by _id'); }
  })();
\""

ROOT_URL="${API_BASE}/"
DOCS_URL="${API_BASE}/docs"
USERS_URL="${API_BASE}/${COLL_NAME}/users"
TMP_ROOT="$(mktemp)"
TMP_USERS1="$(mktemp)"
TMP_USERS2="$(mktemp)"
trap 'rm -f "$TMP_ROOT" "$TMP_USERS1" "$TMP_USERS2"' EXIT

log "Fetching API root summary"
http_get_to_file "$ROOT_URL" "$TMP_ROOT"

FIRST_LATENCY=$(http_get_with_time "$USERS_URL" "$TMP_USERS1")
log "First ${USERS_URL} latency: ${FIRST_LATENCY}s"

SECOND_LATENCY=$(http_get_with_time "$USERS_URL" "$TMP_USERS2")
log "Second ${USERS_URL} latency: ${SECOND_LATENCY}s"

python3 - "$TMP_ROOT" "$TMP_USERS1" "$TMP_USERS2" "$FIRST_LATENCY" "$SECOND_LATENCY" "$CACHE_SLA_MS" "$COLL_NAME" <<'PY'
import json
import sys
from decimal import Decimal
from pathlib import Path

root_path = Path(sys.argv[1])
users1_path = Path(sys.argv[2])
users2_path = Path(sys.argv[3])
first_latency = Decimal(sys.argv[4].strip())
second_latency = Decimal(sys.argv[5].strip())
sla_ms = Decimal(sys.argv[6])
collection = sys.argv[7]

data = json.loads(root_path.read_text())
users_first = json.loads(users1_path.read_text())
users_second = json.loads(users2_path.read_text())

if data.get("cache_enabled") is not True:
    raise SystemExit("API cache is not enabled according to root endpoint")

total_docs = data.get("total_documents", 0)
if total_docs < 1000:
    raise SystemExit(f"API reports total_documents={total_docs}, expected ≥ 1000")

collections = data.get("collections") or {}
coll_info = collections.get(collection)
if not coll_info:
    raise SystemExit(f"Collection '{collection}' absent in API response")

doc_count = coll_info.get("documents_count", 0)
if doc_count < 1000:
    raise SystemExit(f"Collection '{collection}' documents_count={doc_count}, expected ≥ 1000")

per_shard_docs = coll_info.get("per_shard") or {}
if len(per_shard_docs) < 2 or any(v <= 0 for v in per_shard_docs.values()):
    raise SystemExit(f"Collection '{collection}' per-shard stats look invalid: {per_shard_docs}")

shard_hosts = data.get("shards") or {}
required_shards = {"shard1ReplSet", "shard2ReplSet"}
if not required_shards.issubset(shard_hosts.keys()):
    raise SystemExit(f"API shard map missing entries, got {list(shard_hosts.keys())}")

replicas_per_shard = data.get("replicas_per_shard") or {}
if not required_shards.issubset(replicas_per_shard.keys()):
    raise SystemExit(f"API replicas_per_shard missing entries, got {list(replicas_per_shard.keys())}")

replicas_total = data.get("replicas_total", 0)
if replicas_total < 6:
    raise SystemExit(f"API reports replicas_total={replicas_total}, expected ≥ 6")

if data.get("mongo_is_mongos") is not True:
    raise SystemExit("API indicates client is not routed through mongos")

users_first_list = users_first.get("users") or []
if not users_first_list:
    raise SystemExit("First /users call returned empty payload")

if users_first != users_second:
    raise SystemExit("Cached /users response differs from initial response")

if second_latency >= first_latency:
    raise SystemExit(
        f"Second /users request not faster than first ({second_latency}s vs {first_latency}s)"
    )

sla_seconds = sla_ms / Decimal(1000)
if second_latency > sla_seconds:
    raise SystemExit(
        f"Second /users request took {second_latency * 1000:.1f} ms, exceeds SLA {sla_ms} ms"
    )
PY

log "Verify finished."

if [[ "${KEEP}" == "0" ]]; then
  log "KEEP=0 → bringing stack down..."
  ${COMPOSE} --profile core --profile router --profile demo down
fi
