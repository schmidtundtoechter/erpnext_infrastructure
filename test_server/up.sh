#!/bin/bash

# Name des Volumes
VOLUMES="env apps sites logs redis-queue-data redis-cache-data db-data"
echo "Volumes vorbereiten ($VOLUMES)"

for VOLUME_NAME in $VOLUMES; do
  # Überprüfen, ob das Volume bereits existiert
  if ! docker volume inspect $VOLUME_NAME > /dev/null 2>&1; then
    # Volume existiert nicht, also erstellen wir es
    echo "Docker-Volume '$VOLUME_NAME' wird erstellt..."
    docker volume create $VOLUME_NAME
    echo "Docker-Volume '$VOLUME_NAME' erfolgreich erstellt."
  else
    # Volume existiert bereits
    echo "Docker-Volume '$VOLUME_NAME' existiert bereits."
  fi
done

export SSH_PRIVATE_KEY="$(cat ~/.ssh/id_rsa)"
docker compose -f pwd.yml up
