#!/usr/bin/env bash

# 'source' isn't available on all systems, so use . instead
. .env
. deploy-tools.sh

function setEnvironment() {
  deploy-tools.setEnvironment
}

function checkAndCreateDataVolume() {
  local creation_mode=$1
  banner "Check data volume"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_1 "data_storage" "$creation_mode"
}

function up() {
  checkAndCreateDataVolume
  setEnvironment
  deploy-tools.up
}

function start() {
  checkAndCreateDataVolume
  setEnvironment
  deploy-tools.start
}

function stop() {
  checkAndCreateDataVolume "nocreate"
  setEnvironment
  deploy-tools.stop
}

function down() {
  checkAndCreateDataVolume "nocreate"
  setEnvironment
  deploy-tools.down
}

function test() {
  checkAndCreateDataVolume "nocreate"
  setEnvironment

  if [ "$VERBOSITY" = "-v" ]; then
    banner "Test"
    log "Volumes:"
    docker volume ls | grep -E "(${SCENARIO_DATA_VOLUME_1_PATH})"
    log ""
    log "Images:"
    docker image ls | grep mailpit
    log ""
    log "Containers:"
    docker ps -all | grep ${SCENARIO_NAME}_mailpit_container
  fi

  banner "Check Mailpit $SCENARIO_SERVER_NAME - $SCENARIO_NAME"
  deploy-tools.checkContainer "Mailpit (docker)" ${SCENARIO_NAME}_mailpit_container
  return $?
}

function logs() {
  checkAndCreateDataVolume "nocreate"
  setEnvironment
  deploy-tools.logs
}

function backup() {
  checkAndCreateDataVolume
  setEnvironment

  banner "Backup volumes"
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_1_PATH "data_storage" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
}

function restore() {
  checkAndCreateDataVolume
  setEnvironment

  banner "Restore volumes"
  echo "Available backups in $SCENARIO_DATA_BACKUPDIR:"
  ls -1 $SCENARIO_DATA_BACKUPDIR | grep "$SCENARIO_NAME" | grep data_storage | sed "s;${SCENARIO_NAME}_;;" | sed "s;_data_storage.*;;" | sort -u

  if [ -t 0 ]; then
    read -p "Please provide a timestamp to restore from (format: YYYYMMDDHHMMSS) : " TIMESTAMP
    if [ -z "$TIMESTAMP" ]; then
      echo "Error: No timestamp provided."
      exit 1
    fi
  else
    echo "Error: Cannot prompt for input, not running in an interactive shell."
    exit 1
  fi

  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_1_PATH "data_storage" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
}

function update() {
  checkAndCreateDataVolume
  setEnvironment

  banner "Update services"
  docker compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS pull
  echo "Please restart the services to apply updates with down,up command manually!"
}

if [ -z "$1" ]; then
  deploy-tools.printUsage
  exit 1
fi

STEP=$1
shift

deploy-tools.parseArguments $@

if [ $STEP = "up" ]; then
  up
elif [ $STEP = "start" ]; then
  start
elif [ $STEP = "stop" ]; then
  stop
elif [ $STEP = "down" ]; then
  down
elif [ $STEP = "test" ]; then
  test
elif [ $STEP = "logs" ]; then
  logs
elif [ $STEP = "backup" ]; then
  backup
elif [ $STEP = "restore" ]; then
  restore
elif [ $STEP = "update" ]; then
  update
else
  deploy-tools.printUsage
  exit 1
fi

exit $?