#!/bin/bash

# Aktuelles Verzeichnis abrufen
current_dir=$(pwd)

# Überprüfen, ob das aktuelle Verzeichnis mit "frappe_docker" endet
if [[ $current_dir != *"frappe_docker" ]]; then
    echo "Fehler: Das aktuelle Verzeichnis endet nicht mit 'frappe_docker'."
    exit 1  # Skript beenden mit Fehlercode 1
fi

echo -- Shutdown devcontainers
docker compose -p frappe_docker_devcontainer -f .devcontainer/docker-compose.yml down -v

echo -- Remove directory ./development
rm -rf development .devcontainer

# Name des Volumes
VOLUME_NAME="frappe_docker_volume"

# Überprüfen, ob das Volume existiert
if docker volume inspect $VOLUME_NAME > /dev/null 2>&1; then
  # Volume existiert, also entfernen wir es
  echo "Docker-Volume '$VOLUME_NAME' wird entfernt..."
  docker volume rm $VOLUME_NAME
  echo "Docker-Volume '$VOLUME_NAME' erfolgreich entfernt."
else
  # Volume existiert nicht
  echo "Docker-Volume '$VOLUME_NAME' existiert nicht."
fi

echo -- Remove vscode volume
docker volume rm vscode

echo -- Clean repository
git reset --hard

echo -- Remove untracked files and directories
git clean -fd

echo -- Pull and go to main
git pull
git checkout main

