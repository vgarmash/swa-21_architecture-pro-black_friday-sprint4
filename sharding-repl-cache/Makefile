# Self-documenting Makefile for Task-04 (Sharding + Replication + Cache)
.DEFAULT_GOAL := help
SHELL := /bin/bash

# --- Settings ---------------------------------------------------------------
COMPOSE ?= docker compose
PROJECT ?= sharding-repl-cache

# --- Phony targets ----------------------------------------------------------
.PHONY: up-core up-router up-all init demo logs ps down reset verify verify-fast help

##@ Cluster
up-core: ## Поднять только core (config + shards)
	$(COMPOSE) --profile core up -d

up-router: ## Поднять только mongos
	$(COMPOSE) --profile router up -d mongos

up-all: ## Поднять всё (core + mongos + redis + api)
	$(COMPOSE) --profile core --profile router up -d
	$(COMPOSE) up -d redis pymongo_api

init: ## Bootstrap: RS-init (+router-phase если запущен mongos)
	COMPOSE="$(COMPOSE)" WAIT_MONGOS=auto bash scripts/init-bootstrap.sh

demo: ## Демо-данные
	COMPOSE="$(COMPOSE)" bash scripts/demo-populate.sh

down: ## Остановить контейнеры
	$(COMPOSE) down

reset: ## Полный сброс (контейнеры + volumes)
	-$(COMPOSE) down -v --remove-orphans || true
	-@vols=$$(docker volume ls -q | grep -E '^$(PROJECT)_(config1|config2|config3|shard1-[1-3]|shard2-[1-3])$$'); \
	  [ -z "$$vols" ] || docker volume rm -f $$vols

##@ Utils
logs: ## Поток логов mongos
	$(COMPOSE) logs -f mongos

ps: ## Состояние контейнеров
	$(COMPOSE) ps

##@ One-shot
verify: ## Двухфазный one-shot: core→bootstrap(RS)→router→bootstrap(router)→(demo)→checks→(down if KEEP=0)
	KEEP=${KEEP:-0} SKIP_DEMO=${SKIP_DEMO:-0} VERBOSE=${VERBOSE:-0} \
	DOCS=${DOCS:-1000} BATCH=${BATCH:-1000} \
	DB_NAME=${DB_NAME:-somedb} COLL_NAME=${COLL_NAME:-helloDoc} \
	API_BASE=${API_BASE:-http://127.0.0.1:8080} CACHE_SLA_MS=${CACHE_SLA_MS:-100} \
	COMPOSE="$(COMPOSE)" \
	bash scripts/verify.sh

verify-fast: ## То же, но без демо
	SKIP_DEMO=1 KEEP=${KEEP:-0} VERBOSE=${VERBOSE:-0} \
	DB_NAME=${DB_NAME:-somedb} COLL_NAME=${COLL_NAME:-helloDoc} \
	API_BASE=${API_BASE:-http://127.0.0.1:8080} CACHE_SLA_MS=${CACHE_SLA_MS:-100} \
	COMPOSE="$(COMPOSE)" \
	bash scripts/verify.sh

help: ## Показать эту справку
	@awk 'BEGIN {FS=":.*##"; OFS=""} \
		/^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0,5); next} \
		/^[a-zA-Z0-9_.-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
