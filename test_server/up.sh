#!/bin/bash

. .env

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

docker compose -f $YAML_FILE -p $PROJECT_NAME up
