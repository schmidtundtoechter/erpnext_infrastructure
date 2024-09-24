#!/bin/bash

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

echo -- Clean repository
git reset --hard

echo -- Remove untracked files and directories
git clean -fd

echo -- Pull and go to main
git pull
git checkout main

