#!/bin/bash

# Guide-to-Install-Frappe-ERPNext-in-Windows-11-Using-Docker
# A complete Guide to Install Frappe Bench in Windows 11 Using Docker and install Frappe/ERPNext Application

modify_file() {
  local file="$1"          # Der Dateiname
  local old_string="$2"     # Der zu ersetzende String
  local new_string="$3"     # Der neue String

  # Überprüfen, ob die Datei existiert
  if [ -f "$file" ]; then
    # Sicherung der Originaldatei
    mv "$file" "$file.ORIG"
    
    # Ersetzen der Zeile mit sed und Rückschreiben der Ausgabe in die Originaldatei
    sed -e "s;$old_string;$new_string;g" "$file.ORIG" > "$file"

    # Sicherung löschen
    rm "$file.ORIG"

    echo "Datei '$file' wurde erfolgreich geändert."
  else
    echo "Datei '$file' nicht gefunden."
    return 1
  fi
}

# Aktuelles Verzeichnis abrufen
current_dir=$(pwd)

# Überprüfen, ob das aktuelle Verzeichnis mit "frappe_docker" endet
if [[ $current_dir != *"frappe_docker" ]]; then
    echo "Fehler: Das aktuelle Verzeichnis endet nicht mit 'frappe_docker'."
    exit 1  # Skript beenden mit Fehlercode 1
fi

echo "### STEP 2: Only on arm64 because frappe/erpnext:$ERPNEXT_VERSION for the"
echo "    arm64 platform is not in the docker repository and must be build."
echo "    Attention: The version number of erpnext is adapted through example.env."
if [[ "$(docker version --format '{{.Server.Arch}}')" == "arm64" ]]; then
    cp images/production/Containerfile Dockerfile
    export `grep ERPNEXT_VERSION example.env`
    docker build -t frappe/erpnext:$ERPNEXT_VERSION .
fi

echo "### STEP 3: Create devcontainer and VS Code setup"
cp -r devcontainer-example .devcontainer
cp -r development/vscode-example development/.vscode
# Only on MaccOS with M1 or M2; ad check arm or amd platform
if [[ "$(docker version --format '{{.Server.Arch}}')" == "arm64" ]]; then
    echo "### Update devcontainer and docker-compose for M1/M2"
    modify_file .devcontainer/devcontainer.json "linux/amd64" "linux/arm64"
    modify_file .devcontainer/docker-compose.yml "linux/amd64" "linux/arm64"
fi

modify_file .devcontainer/docker-compose.yml "- ..:/workspace" "- frappe_docker_volume:/workspace"
modify_file .devcontainer/docker-compose.yml "#mailpit-data:" "frappe_docker_volume:\n    external: true"

echo "STEP 3.3 Copy reinstall script into development"
cp ../my_erpnext_app/tools/frappe_docker-reinstall.sh ./development/

# Convert script to unix format if windows
if [[ "$OSTYPE" == "msys" ]]; then
  dos2unix ./development/frappe_docker-reinstall.sh
fi

echo "STEP 3.5 Volume vorbereiten (frappe_docker_volume)"
# Name des Volumes
VOLUME_NAME="frappe_docker_volume"

# Überprüfen, ob das Volume bereits existiert
if ! docker volume inspect $VOLUME_NAME > /dev/null 2>&1; then
  # Volume existiert nicht, also erstellen wir es
  echo "Docker-Volume '$VOLUME_NAME' wird erstellt..."
  docker volume create $VOLUME_NAME
  echo "Docker-Volume '$VOLUME_NAME' erfolgreich erstellt."

  echo "STEP 3.5.1 Volume mit Frappe Docker befüllen"

  # Convert TEMP_DIR_UNIX if windows
  if [[ "$OSTYPE" == "msys" ]]; then
    TEMP_DIR_UNIX=$(cygpath -u -a "../frappe_docker")
  else
    TEMP_DIR_UNIX=$(realpath ../frappe_docker)
  fi
  echo "TEMP_DIR_UNIX=$TEMP_DIR_UNIX"

  # Erstelle einen temporären Container, der das Volume mountet
  docker run --rm \
    -v $VOLUME_NAME:/mnt/frappe_docker_volume \
    -v $TEMP_DIR_UNIX:/mnt/tmp_clone \
    ubuntu bash -c "cp -r /mnt/tmp_clone/. /mnt/frappe_docker_volume/"

  echo "Repository content has been successfully copied into the Docker volume."
else
  # Volume existiert bereits
  echo "Docker-Volume '$VOLUME_NAME' existiert bereits."
fi

echo "Check volume content"
docker run --rm \
  -v $VOLUME_NAME:/mnt/frappe_docker_volume \
  ubuntu bash -c "touch /mnt/frappe_docker_volume/development/ICHBINVOLUME"
docker run --rm \
  -v $VOLUME_NAME:/mnt/frappe_docker_volume \
  ubuntu bash -c "ls -la /mnt/frappe_docker_volume/ /mnt/frappe_docker_volume/development"

echo "### STEP 4 Open vscode and install 'Dev Containers' extension"
echo "###  STEP 5 Open frappe_docker folder in VS Code."
echo
echo "--> NOW: Launch the command, from Command Palette (Ctrl + Shift + P) Remote-Containers: Reopen in Container. You can also click in the bottom left corner to access the remote container menu."