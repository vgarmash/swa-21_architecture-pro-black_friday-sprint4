#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# --- Constants ------------------------------------------------------------
CFG_RS="configReplSet"
SH1_RS="shard1ReplSet"
SH2_RS="shard2ReplSet"

# --- Settings -------------------------------------------------------------
PAR_WAIT="${PAR_WAIT:-1}"           # параллельное ожидание RS
WAIT_MONGOS="${WAIT_MONGOS:-auto}"  # 0=пропустить, 1=ждать, auto=если запущен

# 1) Ждём ping демонов (configSrv*, shard*)
if [[ "$PAR_WAIT" == "1" ]]; then
  bg_reset
  bg_run wait_ping configSrv-1 27019
  bg_run wait_ping configSrv-2 27019
  bg_run wait_ping configSrv-3 27019
  bg_run wait_ping shard1-1    27018
  bg_run wait_ping shard1-2    27018
  bg_run wait_ping shard1-3    27018
  bg_run wait_ping shard2-1    27018
  bg_run wait_ping shard2-2    27018
  bg_run wait_ping shard2-3    27018
  bg_wait_all
else
  wait_ping configSrv-1 27019
  wait_ping configSrv-2 27019
  wait_ping configSrv-3 27019
  wait_ping shard1-1    27018
  wait_ping shard1-2    27018
  wait_ping shard1-3    27018
  wait_ping shard2-1    27018
  wait_ping shard2-2    27018
  wait_ping shard2-3    27018
fi

# 2) rs.initiate (идемпотентно)
rs_initiate_if_needed configSrv-1 27019 \
  "{_id:'$CFG_RS', configsvr:true, members:[
     {_id:0, host:'configSrv-1:27019'},
     {_id:1, host:'configSrv-2:27019'},
     {_id:2, host:'configSrv-3:27019'}
  ]}"
rs_initiate_if_needed shard1-1 27018 \
  "{_id:'$SH1_RS', members:[
     {_id:0, host:'shard1-1:27018'},
     {_id:1, host:'shard1-2:27018'},
     {_id:2, host:'shard1-3:27018'}
  ]}"
rs_initiate_if_needed shard2-1 27018 \
  "{_id:'$SH2_RS', members:[
     {_id:0, host:'shard2-1:27018'},
     {_id:1, host:'shard2-2:27018'},
     {_id:2, host:'shard2-3:27018'}
  ]}"

# 3) Ждём PRIMARY
wait_rs_primary configSrv-1 27019

if [[ "$PAR_WAIT" == "1" ]]; then
  bg_reset
  bg_run wait_rs_primary shard1-1    27018
  bg_run wait_rs_primary shard2-1    27018
  bg_wait_all
else
  wait_rs_primary shard1-1    27018
  wait_rs_primary shard2-1    27018
fi

# 4) Router-phase: настройка mongos и шардирование
wants_router=0
val="${WAIT_MONGOS:-auto}"; val="${val,,}"

case "$val" in
  1|true|yes|on)   wants_router=1 ;;
  0|false|no|off)  wants_router=0 ;;
  auto)
    if is_service_running mongos; then wants_router=1; else wants_router=0; fi
    ;;
  *) die "WAIT_MONGOS must be one of: 0|1|auto|true|false|yes|no|on|off" ;;
esac

if [[ "$wants_router" == "1" ]]; then
  log "Starting router phase..."
  wait_ping mongos 27017

  # Добавление шардов
  add_shard_if_needed "$SH1_RS" "shard1-1:27018"
  add_shard_if_needed "$SH2_RS" "shard2-1:27018"

  # Настройка шардирования для коллекции
  DB_NAME="${DB_NAME:-somedb}"
  COLL_NAME="${COLL_NAME:-helloDoc}"
  shard_collection_if_needed "$DB_NAME" "$COLL_NAME"

  log "Bootstrap done (router phase)."
else
  log "Router phase skipped (mongos not running or WAIT_MONGOS=0). Core is ready."
fi
