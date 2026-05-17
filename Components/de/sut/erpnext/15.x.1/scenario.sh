#!/usr/bin/env bash

# 'source' isn't available on all systems, so use . instead
. .env
. deploy-tools.sh

APP_UPGRADE_MARKER=".run-app-upgrade"

# Set some variables
function setEnvironment() {
  deploy-tools.setEnvironment
  if [[ $SCENARIO_TRAEFIK_ENABLE != "true" ]]; then
	log "Traefik is disabled, will publish frontend port on the host so an external proxy can reach it"
    # No Traefik: publish frontend port on the host so an external proxy can reach it
    COMPOSE_FILE_ARGUMENTS="${COMPOSE_FILE_ARGUMENTS} -f docker-compose.ports.yml"
  else
	log "Traefik is enabled, will not publish frontend port on the host"
  fi
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

  # build and run — setEnvironment must be called BEFORE deploy-tools.up because
  # deploy-tools.up re-runs deploy-tools.setEnvironment internally and would overwrite
  # the COMPOSE_FILE_ARGUMENTS extension (e.g. docker-compose.ports.yml) added here.
  setEnvironment
  banner "Create and run container"
  docker compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS up -d
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

  # Bench backup (only if frontend container is running, otherwise we might end up with an incomplete backup and no way to recover)
  local frontend_container="${SCENARIO_NAME}_erpnext_frontend_container"
  if ! docker ps --format '{{.Names}}' | grep -qx "$frontend_container"; then
    banner "Skip bench backup"
    echo "Service $frontend_container is not running. Skipping internal bench backup."
    return 0
  fi

  # Run bench backup in create-site container
  banner "Run bench backup in create-site container"
  local site_name="${SCENARIO_SITE_NAME:-$SCENARIO_TRAEFIK_URL}"
  if ! docker compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS run --rm create-site "bash -lc \"set -e; cd /home/frappe/frappe-bench && \
     bench --site ${site_name} backup --with-files && \
     mkdir -p backups/${SCENARIO_NAME} && \
     if ls sites/${site_name}/private/backups/* >/dev/null 2>&1; then \
       mv sites/${site_name}/private/backups/* backups/${SCENARIO_NAME}/; \
     else \
       echo 'No bench backup files found to move'; \
     fi && \
     ls -l sites/${site_name}/private/backups backups/${SCENARIO_NAME}/ || true\""; then
    logError "Bench backup failed for scenario '$SCENARIO_NAME' and site '$site_name'."
    logError "Retry manually with: docker compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS run --rm create-site bash -lc 'cd /home/frappe/frappe-bench && bench --site ${site_name} backup --with-files'"
    return 1
  fi
}

function restore() {
  # Check data volume (also sets the necessary environment variables)
  checkAndCreateDataVolume

  # Set environment
  setEnvironment

  banner "Restore volumes"

  # Show available timestamps from example: $SCENARIO_DATA_BACKUPDIR/$SCENARIO_NAME_$TIMESTAMP_env.tar.gz
  echo "Available backups in $SCENARIO_DATA_BACKUPDIR:"
  ls -1 $SCENARIO_DATA_BACKUPDIR | grep "${SCENARIO_NAME}_" | grep db-data | sed "s;${SCENARIO_NAME}_;;" | sed "s;_db-data.*;;" | sort -u

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

function normalizeAppsJsonForUpdate() {
  if [[ "$SCENARIO_INSTALL_APPS" == *.json ]]; then
    if [ -f "$SCENARIO_INSTALL_APPS" ]; then
      echo "$SCENARIO_INSTALL_APPS"
      return 0
    fi
    echo "Error: Apps JSON file not found: $SCENARIO_INSTALL_APPS" >&2
    return 1
  fi

  local legacy_json="apps.updated.from-legacy.json"
  IFS=',' read -r -a _legacy_apps <<< "$SCENARIO_INSTALL_APPS"
  local _json="["
  for _i in "${!_legacy_apps[@]}"; do
    local _app="${_legacy_apps[$_i]}"
    local _name=$(echo "$_app" | cut -d'@' -f1)
    local _url=$(echo "$_app" | cut -d'@' -f2 | sed 's/__at__/@/g')
    local _version=$(echo "$_app" | cut -d'@' -f3)
    local _active="true"
    if [[ "$_name" == -* ]]; then
      _active="false"
      _name="${_name:1}"
    fi
    local _comma="," 
    [ $_i -eq $((${#_legacy_apps[@]}-1)) ] && _comma=""
    _json+=$'\n'"  {\"name\": \"$_name\", \"url\": \"$_url\", \"version\": \"$_version\", \"active\": $_active}$_comma"
  done
  _json+=$'\n'"]"
  echo "$_json" > "$legacy_json"
  echo "$legacy_json"
}

function extractMajorFromVersion() {
  local version="$1"
  if [[ "$version" =~ ^version-([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$version" =~ ^v?([0-9]+)(\..*)?$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

function latestVersionForRepo() {
  local repo_url="$1"
  local current_version="$2"
  local major=""
  local latest=""
  local matching=()
  mapfile -t tags < <(git ls-remote --tags --refs "$repo_url" 2>/dev/null | awk '{print $2}' | sed 's#refs/tags/##' | sort -V)

  if [ ${#tags[@]} -eq 0 ]; then
    echo "$current_version"
    return 0
  fi

  major=$(extractMajorFromVersion "$current_version" || true)
  if [ -n "$major" ]; then
    for tag in "${tags[@]}"; do
      if [[ "$tag" =~ ^v?${major}(\..*)?$ ]]; then
        matching+=("$tag")
      fi
    done
  fi

  if [ ${#matching[@]} -gt 0 ]; then
    latest="${matching[-1]}"
  else
    latest="${tags[-1]}"
  fi

  echo "$latest"
}

function printCoreVersionSuggestion() {
  local app_name="$1"
  local repo_url="$2"
  local current_version="$3"
  local latest_version=$(latestVersionForRepo "$repo_url" "$current_version")
  if [ "$latest_version" = "$current_version" ]; then
    echo "$app_name stays on $current_version"
  else
    echo "$app_name: $current_version -> $latest_version"
  fi
}

function createUpdatedAppsJsonCopy() {
  local source_json="$1"
  local updated_json="${source_json%.json}.updated.json"

  python3 - "$source_json" "$updated_json" <<'PY'
import json
import sys

source_json = sys.argv[1]
updated_json = sys.argv[2]

with open(source_json, "r", encoding="utf-8") as fh:
    apps = json.load(fh)

with open(updated_json, "w", encoding="utf-8") as fh:
    json.dump(apps, fh, indent=2)
    fh.write("\n")
PY

  while IFS=$'\t' read -r name url version; do
    local latest_version=$(latestVersionForRepo "$url" "$version")
    python3 - "$updated_json" "$name" "$latest_version" <<'PY'
import json
import sys

path, name, version = sys.argv[1:4]
with open(path, "r", encoding="utf-8") as fh:
    apps = json.load(fh)

for app in apps:
    if app.get("name") == name:
        app["version"] = version

with open(path, "w", encoding="utf-8") as fh:
    json.dump(apps, fh, indent=2)
    fh.write("\n")
PY
    echo "$name: $version -> $latest_version" >&2
  done < <(python3 - "$source_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    apps = json.load(fh)

for app in apps:
    print(f"{app['name']}\t{app['url']}\t{app['version']}")
PY
)

  echo "$updated_json"
}

function update() {
  # Check data volume so the update marker can be written to the persistent sites volume.
  checkAndCreateDataVolume

  banner "Collect latest version suggestions"

  local apps_json
  apps_json=$(normalizeAppsJsonForUpdate) || exit 1

  banner "Create updated apps.json copy"
  local updated_apps_json
  updated_apps_json=$(createUpdatedAppsJsonCopy "$apps_json") || exit 1
  echo "Created $updated_apps_json"
  echo "Contents of $updated_apps_json:"
  cat "$updated_apps_json"

  banner "Suggested core version updates"
  printCoreVersionSuggestion "FRAPPE_VERSION" "https://github.com/frappe/frappe.git" "$FRAPPE_VERSION"
  printCoreVersionSuggestion "ERPNEXT_VERSION" "https://github.com/frappe/erpnext.git" "$ERPNEXT_VERSION"

  # Open permissions to docker sock
  deploy-tools.setDockerSockPermissions

  # Pull/build is intentionally part of update, not normal up.
  setEnvironment
  banner "Pull Docker images"
  # Only pull registry-based images; erpnext_image is built locally and cannot be pulled
  docker compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS pull db redis-queue redis-cache || exit 1
  banner "Build Docker images"
  docker compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS build --pull || exit 1

  banner "Mark app upgrade for next up"
  docker compose -p $SCENARIO_NAME $COMPOSE_FILE_ARGUMENTS run --rm --no-deps --entrypoint bash frontend \
    -lc "touch sites/$APP_UPGRADE_MARKER && ls -l sites/$APP_UPGRADE_MARKER" || exit 1
  echo "Created app upgrade marker: sites/$APP_UPGRADE_MARKER"
  echo "Run scenario.deploy <scenario> down,up to execute app upgrades and migrations."
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
