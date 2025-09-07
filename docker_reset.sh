#!/bin/bash
# Полная очистка Docker: контейнеры, образы, сети и тома

echo "Останавливаю все контейнеры..."
docker stop $(docker ps -q) 2>/dev/null

echo "Удаляю все контейнеры..."
docker rm -f $(docker ps -aq) 2>/dev/null

echo "Удаляю все образы..."
docker rmi -f $(docker images -q) 2>/dev/null

echo "Удаляю все сети (кроме default, bridge, host, none)..."
docker network prune -f

echo "Удаляю все тома..."
docker volume prune -f

echo "Готово! Docker окружение очищено."
