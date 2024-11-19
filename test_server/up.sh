#!/bin/bash

# Name des Volumes
VOLUME_NAME="frappe_docker_testvolume"
echo "Volume vorbereiten ($VOLUME_NAME)"

# Überprüfen, ob das Volume bereits existiert
if ! docker volume inspect $VOLUME_NAME > /dev/null 2>&1; then
  # Volume existiert nicht, also erstellen wir es
  echo "Docker-Volume '$VOLUME_NAME' wird erstellt..."
  docker volume create $VOLUME_NAME
  echo "Docker-Volume '$VOLUME_NAME' erfolgreich erstellt."

  # Erstelle installation directoy
  docker run --rm \
    -v $VOLUME_NAME:/workspace \
    ubuntu bash -c "mkdir /workspace/installation ; chmod 777 /workspace/installation"

else
  # Volume existiert bereits
  echo "Docker-Volume '$VOLUME_NAME' existiert bereits."
fi

docker compose up
