#!/bin/bash
# Останавливаем и удаляем все контейнеры
echo "Остановка и удаление всех контейнеров..."
if [ -n "$(docker ps -a -q)" ]; then
    docker stop $(docker ps -a -q)
    docker rm $(docker ps -a -q)
else
    echo "Нет контейнеров для остановки и удаления."
fi

# Удаляем все volumes
echo "Удаление всех Docker volumes..."
if [ -n "$(docker volume ls -q)" ]; then
    docker volume rm $(docker volume ls -q)
else
    echo "Нет volumes для удаления."
fi

echo "Скрипт завершен."
