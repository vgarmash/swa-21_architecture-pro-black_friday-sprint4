#!/usr/bin/env bash
set -Eeuo pipefail

# --- Config ---------------------------------------------------------------
COMPOSE="${COMPOSE:-docker compose}"

# --- Utils ----------------------------------------------------------------
log()  { printf "\033[36m[%s]\033[0m %s\n" "$(date +%H:%M:%S)" "$*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

compose_exec() {
  local service="$1"; shift
  local runtime
  if command -v podman >/dev/null 2>&1 && ${COMPOSE} --version 2>&1 | grep -qi podman; then
    runtime="podman"
  else
    runtime="docker"
  fi
  ${runtime} exec -i "$service" bash -c "$*"
}

mongo_eval() {
  local service="$1" port="$2" js="$3"
  compose_exec "$service" "mongosh --quiet --port ${port} --eval \"$js\""
}

mongo_eval_stdin() {
  local service="$1" port="$2"
  local runtime
  if command -v podman >/dev/null 2>&1 && ${COMPOSE} --version 2>&1 | grep -qi podman; then
    runtime="podman"
  else
    runtime="docker"
  fi
  ${runtime} exec -i "$service" mongosh --quiet --port "$port" <<'MONGO_JS_END'
$3
MONGO_JS_END
}

# --- Generic spinner -------------------------------------------------------
# spin_until <timeout_sec> <sleep_sec> <on_timeout_msg> <fn> [args...]
spin_until() {
  local timeout="$1" sleep_s="$2" msg="$3"; shift 3
  local start ts
  start=$(date +%s)
  until "$@"; do
    ts=$(($(date +%s)-start))
    (( ts > timeout )) && die "$msg (waited ${ts}s)"
    sleep "$sleep_s"
  done
}

# --- Predicates (true/0 == success) ---------------------------------------
is_ping_ok() {
  local service="$1" port="$2"
  mongo_eval "$service" "$port" 'db.adminCommand({ping:1}).ok' 2>/dev/null | grep -q '^1$'
}

is_primary_ok() {
  local service="$1" port="$2"
  mongo_eval "$service" "$port" '(db.hello().isWritablePrimary?1:0)' 2>/dev/null | grep -q '^1$'
}

# --- Waiters ---------------------------------------------------------------
wait_ping() {
  local service="$1" port="$2" timeout="${3:-180}"
  log "Waiting ping: $service:$port (timeout ${timeout}s)"
  spin_until "$timeout" 2 "Timeout waiting PING for $service:$port" is_ping_ok "$service" "$port"
  log "Ping OK: $service:$port"
}

wait_primary() {
  local service="$1" port="$2" timeout="${3:-240}"
  log "Waiting PRIMARY: $service:$port (timeout ${timeout}s)"
  spin_until "$timeout" 3 "Timeout waiting PRIMARY for $service:$port" is_primary_ok "$service" "$port"
  log "PRIMARY ready: $service"
}

rs_has_primary() {
  local service="$1" port="$2"
  mongo_eval "$service" "$port" 'rs.status().members.some(m=>m.state===1)' 2>/dev/null | grep -q '^true$'
}

wait_rs_primary() {
  local service="$1" port="$2" timeout="${3:-240}"
  log "Waiting for RS PRIMARY via $service:$port (timeout ${timeout}s)"
  spin_until "$timeout" 3 "Timeout waiting RS PRIMARY via $service:$port" rs_has_primary "$service" "$port"
  log "RS has PRIMARY (checked via $service)"
}

# --- Mongo helpers ---------------------------------------------------------
rs_initiate_if_needed() {
  local service="$1" port="$2" cfg_js="$3"
  if mongo_eval "$service" "$port" 'rs.status().ok' 2>/dev/null | grep -q '^1$'; then
    log "ReplicaSet already initiated on $service"
  else
    log "Initiating ReplicaSet on $service"
    mongo_eval "$service" "$port" "rs.initiate(${cfg_js});"
  fi
}

add_shard_if_needed() {
  local shard_name="$1" seed="$2"
  if compose_exec mongos 'mongosh --quiet --eval "db.getSiblingDB(\"admin\").runCommand({listShards:1}).shards.map(s=>s._id).join(\",\")"' \
      | grep -qw "$shard_name"; then
    log "Shard '$shard_name' already added"
  else
    log "Adding shard: $shard_name/$seed"
    compose_exec mongos "mongosh --quiet --eval \"sh.addShard('$shard_name/$seed')\""
  fi
}

# --- Parallel helpers ------------------------------------------------------
BG_PIDS=()

bg_reset()      { BG_PIDS=(); }
bg_run()        { ("$@") & BG_PIDS+=($!); }
bg_wait_all() {
  local failed=0
  for pid in "${BG_PIDS[@]:-}"; do
    if ! wait "$pid"; then failed=$((failed+1)); fi
  done
  BG_PIDS=()
  (( failed == 0 )) || die "One or more background tasks failed ($failed)"
}
