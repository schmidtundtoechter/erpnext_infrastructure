#!/bin/bash

SITE_NAME=$1
SCENARIO_INSTALL_APPS=$2
if [ -z "$SCENARIO_INSTALL_APPS" -o -z "$SITE_NAME" ]; then
    echo "Error: Missing required arguments."
    echo "Usage: $0 <site-name> <install-apps>"
    exit 1
fi

# T.1: JSON file support
# If SCENARIO_INSTALL_APPS ends in .json, load app list from that file.
# If it contains inline app data, print the JSON equivalent as a migration hint.
if [[ "$SCENARIO_INSTALL_APPS" == *.json ]]; then
    json_file="$SCENARIO_INSTALL_APPS"
    # Resolve bare filename (no path) to /tmp/<filename> (mounted from scenario dir)
    if [[ "$json_file" != */* ]]; then
        json_file="/tmp/$json_file"
    fi
    if [ ! -f "$json_file" ]; then
        echo "Error: Apps JSON file not found: $json_file"
        exit 1
    fi
    echo "--iua- Loading apps from JSON file: $json_file"
    # active=false -> prepend "-" to trigger remove_app; missing active defaults to install
    SCENARIO_INSTALL_APPS=$(jq -r '.[] | (if .active == false then "-" else "" end) + .name + "@" + .url + "@" + .version' "$json_file" | tr '\n' ',' | sed 's/,$//')
    echo "--iua- Loaded apps: $SCENARIO_INSTALL_APPS"
else
    # Inline app data – print JSON equivalent as migration hint
    echo "--iua- TIPP: SCENARIO_INSTALL_APPS kann auf eine JSON-Datei 'apps.json' im Scenario-Verzeichnis zeigen."
    echo "--iua- Aequivalenter JSON-Inhalt (als apps.json speichern, dann SCENARIO_INSTALL_APPS=apps.json setzen):"
    IFS=',' read -r -a _hint_apps <<< "$SCENARIO_INSTALL_APPS"
    echo "["
    for _i in "${!_hint_apps[@]}"; do
        _app="${_hint_apps[$_i]}"
        _n=$(echo "$_app" | cut -d'@' -f1)
        _u=$(echo "$_app" | cut -d'@' -f2)
        _v=$(echo "$_app" | cut -d'@' -f3)
        _comma=","
        [ $_i -eq $((${#_hint_apps[@]}-1)) ] && _comma=""
        echo "  {\"name\": \"$_n\", \"url\": \"$_u\", \"version\": \"$_v\"}$_comma"
    done
    echo "]"
fi

apps_installed=()

echo "Calling $0 in site $SITE_NAME"

# Method to install or upgrade apps
function install_upgrade_app() {
    repo=$1
    app=$2
    version=$3

    echo "Installing or upgrading $app app from $repo"

    # Get or update app
    # Get base of repot without the ending ".git"
    if [ ! -d apps/$app ]; then
        echo "Installing $app app"
        bench get-app $app $repo --branch $version
    fi

    # Fix git refs to ensure all remote branches/tags are fetchable
    if [ -f /home/frappe/frappe-bench/fix-git-refs.sh ]; then
        /home/frappe/frappe-bench/fix-git-refs.sh apps/$app || true
    fi

    echo "Updating $app app to version $version"
    pushd apps/$app > /dev/null

    # TODO: Hier sollte bench update bevorzugt werden, damit apps.json und requirements.txt auch aktualisiert werden
	# TODO: Hier ist auch unklar, warum erpnext und frappe kein .git Verzeichnis haben
	# TODO: auch bench und pip und das betriebssystem (in alle containern) sollte geupdatet werden
	# TODO: Check /var/run/docker.sock permissions if docker commands fail
	# TODO: Wenn die python version wechselt, müssen die envs neu gebaut werden!

    # Check ref already available in remotes or tags
    if git show-ref --verify --quiet refs/remotes/upstream/$version; then
        echo "Ref $version already exists in remotes/upstream"
    elif git show-ref --verify --quiet refs/tags/$version; then
        echo "Ref $version already exists in tags"
    else
        echo "Adding refs"
        git config --add remote.upstream.fetch "+refs/heads/$version:refs/remotes/upstream/$version"
        git config --add remote.upstream.fetch "+refs/tags/$version:refs/tags/$version"
    fi
    git fetch upstream $version
    git checkout $version
    # T.2: Only pull if on a branch – skip for detached HEAD (tag checkout)
    if git symbolic-ref -q HEAD > /dev/null 2>&1; then
        echo "Pulling latest changes for $app app (branch)"
        git pull
    else
        echo "Detached HEAD (tag $version) – skipping git pull for $app"
    fi
    popd > /dev/null

    # Install app only if it is not installed
    bench --site ${SITE_NAME} install-app $app
    if [ $? -eq 0 ]; then
        echo "$app app installed successfully"
    else
        echo "Error installing $app app"
    fi
    apps_installed+=($app)
}

function remove_app() {
	app_name=$1

	# Remove app from site
	echo "Uninstalling $app_name app from site ${SITE_NAME}"
	bench --site ${SITE_NAME} uninstall-app -y $app_name

	# Remove app from apps directory
	echo "Removing $app_name app from apps directory"
	bench remove-app $app_name

	# Remove app from sites/apps.txt
	echo "Removing $app_name from sites/apps.txt"
	sed -i "/$app_name/d" sites/apps.txt

	# Force remove app directory
	echo "Force removing $app_name directory"
	rm -rf apps/$app_name
}

echo "--iua- Installing or upgrading apps from SCENARIO_INSTALL_APPS: $SCENARIO_INSTALL_APPS"

# Add default apps
apps_installed+=(frappe)
apps_installed+=(erpnext)

# Install or update apps from SCENARIO_INSTALL_APPS
# like "bench update --pull"
IFS=',' read -r -a apps <<< "$SCENARIO_INSTALL_APPS"
for app in "${apps[@]}"; do
    # Get the app name and version
    app_name=$(echo $app | cut -d'@' -f1)
    app_url=$(echo $app | cut -d'@' -f2)
    app_version=$(echo $app | cut -d'@' -f3)

    # if app_name starts with "-" then uninstall it
    if [[ $app_name == -* ]]; then
        real_name="${app_name:1}"
        echo "--iua- Deinstalling app $real_name (active=false)"
        remove_app "$real_name"
        continue
    fi

	# Replace __at__ with @ in app_url
	app_url=${app_url//__at__/@}
	
    install_upgrade_app $app_url $app_name $app_version
done

echo "--iua- Installed or upgraded apps: ${apps_installed[@]}"

# Remove other apps
echo "--iua- Removing other apps that are not in SCENARIO_INSTALL_APPS"
for app in apps/*/; do
	app_name=$(basename "$app")
	if [[ ! " ${apps_installed[@]} " =~ " ${app_name} " ]]; then
		remove_app $app_name
	else
		echo "Keeping $app_name app"
	fi
done
pwd
ls

# Update requirements
echo "--iua- Updating requirements"
# TODO: Fix error messages when erpnext or frappe are not on a branch
bench update --requirements

# Migrate site
echo "--iua- Migrating site ${SITE_NAME}"
bench --site ${SITE_NAME} migrate;

# Rebuild assets
echo "--iua- Rebuilding assets"
# TODO: Optimize, needs many resources
#bench build

# Set developer mode
echo "--iua- Setting developer mode and server script enabled"
bench set-config -g developer_mode 1
bench set-config -g server_script_enabled 1
bench setup requirements --dev

# Clear cache
echo "--iua- Clearing cache"
bench --site ${SITE_NAME} clear-cache
bench --site ${SITE_NAME} clear-website-cache

# All containers need to restart after installation: This is done in create-site container startup script
