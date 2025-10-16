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

log "Verify one-shot flow (up → init → demo? → checks → down?)"
${COMPOSE} --profile core --profile router up -d

# Init bootstrap (idempotent)
WAIT_MONGOS=1 bash "$SCRIPT_DIR/init-bootstrap.sh"

# Optional populate
if [[ "${SKIP_DEMO}" == "0" ]]; then
  bash "$SCRIPT_DIR/demo-populate.sh"
fi

# Ensure mongos
wait_ping mongos 27017

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

log "Verify finished."

if [[ "${KEEP}" == "0" ]]; then
  log "KEEP=0 → bringing stack down..."
  ${COMPOSE} --profile core --profile router down
fi
