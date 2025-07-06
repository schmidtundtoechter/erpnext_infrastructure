#!/usr/bin/env bash

# 'source' isn't available on all systems, so use . instead
. .env
. deploy-tools.sh

# Set some variables
function setEnvironment() {
  deploy-tools.setEnvironment
}

function checkAndCreateDataVolume() {
  banner "Check data volume"
  # Second argument is for creating the mount point for docker compose
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_1 "env"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_2 "apps"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_3 "sites"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_4 "logs"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_5 "redis-queue-data"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_6 "redis-cache-data"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_7 "db-data"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_8 "assets"
  sleep 2 # Wait for volumes to be created
}

function up() {
  # Check data volume
  checkAndCreateDataVolume

  # Restore backup
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_1_RESTORESOURCE $SCENARIO_DATA_VOLUME_1_PATH 1
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_2_RESTORESOURCE $SCENARIO_DATA_VOLUME_2_PATH 1
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_3_RESTORESOURCE $SCENARIO_DATA_VOLUME_3_PATH 1

  # build before up
  deploy-tools.setEnvironment
  docker-compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS build

  deploy-tools.up
}

function start() {
  # Check data volume
  checkAndCreateDataVolume

  deploy-tools.start
}

function stop() {
  # Check data volume
  checkAndCreateDataVolume

  deploy-tools.stop
}

function down() {
  # Check data volume
  checkAndCreateDataVolume

  deploy-tools.down
}

function test() {
  # Check data volume
  checkAndCreateDataVolume

  # Set environment
  setEnvironment

  # Print volumes, images, containers and files
  if [ "$VERBOSITY" = "-v" ]; then
    banner "Test"
    log "Volumes:"
    docker volume ls | grep -E "(${SCENARIO_DATA_VOLUME_1_PATH}|${SCENARIO_DATA_VOLUME_2_PATH})"
    log ""
    log "Images:"
    docker image ls | grep erpnext
    log ""
    log "Containers:"
    docker ps -all | grep ${SCENARIO_NAME}_erpnext_frontend_container
  fi

  # Check erpnext status
  banner "Check erpnext $SCENARIO_SERVER_NAME - $SCENARIO_NAME"
  deploy-tools.checkContainer "erpnext (docker)" ${SCENARIO_NAME}_erpnext_frontend_container
  return $? # Return the result of the last command
}

function logs() {
  # Check data volume
  checkAndCreateDataVolume

  deploy-tools.logs
}

function backup() {
  # Check data volume (also sets the necessary environment variables)
  checkAndCreateDataVolume

  # Set environment
  setEnvironment

  banner "Backup volumes"
  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_1_PATH "env" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_2_PATH "apps" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_3_PATH "sites" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_4_PATH "logs" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_5_PATH "redis-queue-data" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_6_PATH "redis-cache-data" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_7_PATH "db-data" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.backupVolume SCENARIO_DATA_VOLUME_8_PATH "assets" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
}

function restore() {
  # Check data volume (also sets the necessary environment variables)
  checkAndCreateDataVolume

  # Set environment
  setEnvironment

  banner "Restore volumes"

  # Show available timestamps from example: $SCENARIO_DATA_BACKUPDIR/$SCENARIO_NAME_$TIMESTAMP_env.tar.gz
  echo "Available backups in $SCENARIO_DATA_BACKUPDIR:"
  ls -1 $SCENARIO_DATA_BACKUPDIR | grep "$SCENARIO_NAME" | grep db-data | sed "s;${SCENARIO_NAME}_;;" | sed "s;_db-data.*;;" | sort -u

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

  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_1_PATH "env" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_2_PATH "apps" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_3_PATH "sites" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_4_PATH "logs" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_5_PATH "redis-queue-data" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_6_PATH "redis-cache-data" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_7_PATH "db-data" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
  deploy-tools.restoreVolume SCENARIO_DATA_VOLUME_8_PATH "assets" $SCENARIO_NAME $TIMESTAMP "$SCENARIO_DATA_BACKUPDIR"
}

# Scenario vars
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
else
  deploy-tools.printUsage
  exit 1
fi

exit $?
