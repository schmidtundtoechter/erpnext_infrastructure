#!/bin/bash

SITE_NAME=$1
SCENARIO_INSTALL_APPS=$2
if [ -z "$SCENARIO_INSTALL_APPS" -o -z "$SITE_NAME" ]; then
    echo "Error: Missing required arguments."
    echo "Usage: $0 <site-name> <install-apps>"
    exit 1
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
        bench get-app $app $repo
    fi
    echo "Updating $app app to version $version"
    pushd apps/$app > /dev/null
    git checkout $version
    echo "Pulling latest changes for $app app"
    git pull
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
}

echo "Installing or upgrading apps (SCENARIO_INSTALL_APPS=${SCENARIO_INSTALL_APPS})"

# Add default apps
apps_installed+=(frappe)
apps_installed+=(erpnext)

# Install apps from SCENARIO_INSTALL_APPS
IFS=',' read -r -a apps <<< "$SCENARIO_INSTALL_APPS"
for app in "${apps[@]}"; do
    # Get the app name and version
    app_name=$(echo $app | cut -d'@' -f1)
    app_url=$(echo $app | cut -d'@' -f2)
    app_version=$(echo $app | cut -d'@' -f3)

    # if app_name doesn't start with "-" then it is a valid app
    if [[ $app_name == -* ]]; then
        echo "Skipping app $app_name"
        continue
    fi
    install_upgrade_app $app_url $app_name $app_version
done

echo "Installed or upgraded apps: ${apps_installed[@]}"

# Remove other apps
pushd apps > /dev/null
for app in */; do
    app_name=${app%/}
    if [[ ! " ${apps_installed[@]} " =~ " ${app_name} " ]]; then
        remove_app $app_name
    else
        echo "Keeping $app_name app"
    fi
done
pwd
ls
popd > /dev/null

bench --site ${SITE_NAME} migrate;

# Set developer mode
bench set-config -g developer_mode 1
bench set-config -g server_script_enabled 1
bench --site ${SITE_NAME} clear-cache
bench setup requirements --dev

# TODO: All containers need to restart after installation
