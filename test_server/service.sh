#!/bin/bash

. .env

function local.up() {
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

  docker compose -f $DOCKER_COMPOSE_FILE -p $PROJECT_NAME up -d
}

function local.restart() {
  docker compose -f $DOCKER_COMPOSE_FILE -p $PROJECT_NAME restart
}

function local.down() {
  docker compose -f $DOCKER_COMPOSE_FILE -p $PROJECT_NAME down --volumes
}

function local.logs() {
  docker compose -f $DOCKER_COMPOSE_FILE -p $PROJECT_NAME logs -f
}

function local.install_update() {
  docker exec -i  ${PROJECT_NAME}-frontend-1 /bin/bash -s <<EOL
  pwd
  mkdir -p ~/.ssh;
  echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa;
  chmod 600 ~/.ssh/id_rsa;
  if [ ! -d /home/frappe/frappe-bench/apps/test12 ]; then
      echo "App test12 does not exist - cloning";
      GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" bench get-app git@github.com:larsmaeurer/test12.git;
  else
      echo "App test12 already exists - pulling latest changes";
      cd /home/frappe/frappe-bench/apps/test12;
      GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git pull;
  fi;
  rm -rf ~/.ssh/id_rsa

  echo "Install test12 app and migrate";
  bench --site $SITE install-app test12;
  bench --site $SITE migrate;
EOL

  local.restart
}

function callRemote() {
  echo "Calling remote command $1"

  # Assure remote path
  ssh -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST "mkdir -p $REMOTE_PATH"

  # Test remote directory
  ssh -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST "test -d $REMOTE_PATH" || { echo "Remote directory $REMOTE_PATH not found. Exiting..."; exit 1; }

  # Sync files
  rsync -avz -e "ssh -o StrictHostKeyChecking=no -p $REMOTE_PORT" ./ $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/
  
  # Call remote command
  ssh -o StrictHostKeyChecking=no -p $REMOTE_PORT $REMOTE_USER@$REMOTE_HOST "bash -s" <<EOL
    cd $REMOTE_PATH
    echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa;
    ./service.sh $@
    rm -rf ~/.ssh/id_rsa
EOL
}

### Main ###

# Check first argument as command
if [ -z "$1" ]; then
  echo "No command given."
  echo "Usage: ./service.sh <command>"
  echo "Available commands:"
  echo "  local.up"
  echo "  local.restart"
  echo "  local.down"
  echo "  local.logs"
  echo "  local.install_update"
  echo "  remote.up"
  echo "  remote.restart"
  echo "  remote.down"
  echo "  remote.logs"
  echo "  remote.install_update"
  echo "Exiting..."
  exit 1
fi
command=$1
shift

REMOTE=false
# if command starts with "remote." replace it with local and set REMOTE to true
if [[ $command == remote.* ]]; then
  command=${command/remote./local.}
  REMOTE=true
fi

# Check if function exists
if ! declare -f $command > /dev/null; then
  echo "Command $command not found. Exiting..."
  exit 1
fi

# Execute command remotely or locally
if [ "$REMOTE" = true ]; then
  callRemote $command $@
else
  $command $@
fi
