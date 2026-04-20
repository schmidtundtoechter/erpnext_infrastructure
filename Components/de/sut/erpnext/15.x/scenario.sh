#!/usr/bin/env bash

# 'source' isn't available on all systems, so use . instead
. .env
. deploy-tools.sh

# Set some variables
function setEnvironment() {
  deploy-tools.setEnvironment
}

function checkAndCreateDataVolume() {
  local creation_mode=$1
  banner "Check data volume"
  # Second argument is for creating the mount point for docker compose
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_1 "env" "$creation_mode"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_2 "apps" "$creation_mode"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_3 "sites" "$creation_mode"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_4 "logs" "$creation_mode"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_5 "redis-queue-data" "$creation_mode"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_6 "redis-cache-data" "$creation_mode"
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_7 "db-data" "$creation_mode"
  sleep 2 # Wait for volumes to be created
  deploy-tools.checkAndCreateDataVolume SCENARIO_DATA_VOLUME_8 "assets" "$creation_mode"
  sleep 2 # Wait for volumes to be created
}

function up() {
  # Check data volume
  checkAndCreateDataVolume

  # Restore backup
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_1_RESTORESOURCE $SCENARIO_DATA_VOLUME_1_PATH 1
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_2_RESTORESOURCE $SCENARIO_DATA_VOLUME_2_PATH 1
  #deploy-tools.checkAndRestoreDataVolume $SCENARIO_DATA_VOLUME_3_RESTORESOURCE $SCENARIO_DATA_VOLUME_3_PATH 1

  # Open permissions to docker sock
  deploy-tools.setDockerSockPermissions

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
  # Check data volume (nocreate)
  checkAndCreateDataVolume "nocreate"

  deploy-tools.stop
}

function down() {
  # Check data volume (nocreate)
  checkAndCreateDataVolume "nocreate"

  deploy-tools.down
}

function test() {
  # Check data volume (nocreate)
  checkAndCreateDataVolume "nocreate"

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
  # Check data volume (nocreate)
  checkAndCreateDataVolume "nocreate"

  deploy-tools.logs
}

function backup() {
  # Check data volume (also sets the necessary environment variables)
  checkAndCreateDataVolume

  # Set environment
  setEnvironment

  # TODO: Muss das wirklich alles gebackuped werden?
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

  # Run bench backup in create-site container
  banner "Run bench backup in create-site container"
  docker-compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS run --rm create-site "bash -c \"cd /home/frappe/frappe-bench && \
     bench --site ${SCENARIO_SERVER_NAME} backup --with-files && \
     mkdir -p backups/${SCENARIO_NAME} && \
     mv sites/${SCENARIO_SERVER_NAME}/private/backups/* backups/${SCENARIO_NAME}/ && \
     ls -l sites/${SCENARIO_SERVER_NAME}/private/backups backups/${SCENARIO_NAME}/\""
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

  TIMESTAMP="$SCENARIO_DATA_BACKUPTIMESTAMP"
  echo "Configured timestamp: $TIMESTAMP"

  if [ -t 0 ]; then
    read -p "Please provide a timestamp to restore from (format: YYYYMMDDHHMMSS) [$TIMESTAMP]: " TS
	if [ ! -z "$TS" ]; then
	  TIMESTAMP=$TS
	fi
    if [ -z "$TIMESTAMP" ]; then
      echo "Error: No timestamp provided."
      exit 1
    fi
	echo "Using timestamp: $TIMESTAMP"
  else
    if [ -z "$TIMESTAMP" ]; then
		echo "Error: Cannot prompt for input, not running in an interactive shell."
		exit 1
	fi
	echo "Non-interactive shell detected. Using provided timestamp: $TIMESTAMP"
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

function update() {
  # Check data volume (also sets the necessary environment variables)
  checkAndCreateDataVolume

  # Set environment
  setEnvironment

  banner "Update services"

  # Restart create-site container which automatically calls install_upgrade_apps.sh
  docker-compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS run --rm create-site
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
elif [ $STEP = "update" ]; then
  update
else
  deploy-tools.printUsage
  exit 1
fi

exit $?
