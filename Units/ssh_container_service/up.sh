#!/bin/bash

# Name des Volumes
VOLUME_NAME="testconfigvolume"

# Überprüfen, ob das Volume bereits existiert
if ! docker volume inspect $VOLUME_NAME > /dev/null 2>&1; then
  # Volume existiert nicht, also erstellen wir es
  echo "Docker-Volume '$VOLUME_NAME' wird erstellt..."
  docker volume create $VOLUME_NAME
  echo "Docker-Volume '$VOLUME_NAME' erfolgreich erstellt."
fi

docker compose up -d