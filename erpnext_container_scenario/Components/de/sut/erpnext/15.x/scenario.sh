#!/usr/bin/env bash

# 'source' isn't available on all systems, so use . instead
. .env
. deploy-tools.sh

# TODO: Deploy-tools und basedefaults mit Version versehen
# TODO data volume als env ???

# Set some variables
function setEnvironment() {
  deploy-tools.setEnvironment
}

function checkAndCreateDataVolume() {
  banner "Check data volume"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_1 "env"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_2 "apps"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_3 "sites"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_4 "logs"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_5 "redis-queue-data"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_6 "redis-cache-data"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_7 "db-data"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_8 "assets"
}

function up() {
  # Check data volume
  checkAndCreateDataVolume

  # Restore backup
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_1_RESTORESOURCE $SCENARIO_DATA_VOLUME_1_PATH 1
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_2_RESTORESOURCE $SCENARIO_DATA_VOLUME_2_PATH 1
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_3_RESTORESOURCE $SCENARIO_DATA_VOLUME_3_PATH 1

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
else
  deploy-tools.printUsage
  exit 1
fi

exit $?
