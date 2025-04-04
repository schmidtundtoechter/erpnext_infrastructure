#!/bin/bash

SCENARIO_SERVER_NAME=$1
if [ -z "$SCENARIO_SERVER_NAME" ]; then
    echo "Usage: $0 <site-name>"
    exit 1
fi

echo "Calling $0 in site $SCENARIO_SERVER_NAME"

# Method to install or upgrade apps
function install_upgrade_app() {
    repo=$1
    app=$2

    echo "Installing or upgrading $app app from $repo"

    # Get or update app
    # Get base of repot without the ending ".git"
    if [ ! -d apps/$app ]; then
        echo "Installing $app app"
        bench get-app $app $repo
    else
        echo "Updating $app app"
        pushd apps/$app > /dev/null
        git pull
        popd > /dev/null
    fi

    # Install app only if it is not installed
    bench --site ${SCENARIO_SERVER_NAME} install-app $app
}

# This script is called from the main script
install_upgrade_app https://github.com/schmidtundtoechter/ersteingabe_lead.git ersteingabe_lead
install_upgrade_app https://github.com/schmidtundtoechter/sut_app_ueag.git sut_app_ueag
install_upgrade_app https://github.com/frappe/hrms.git hrms
install_upgrade_app https://github.com/schmidtundtoechter/sut_app_datev_export.git sut_app_datev_export

bench --site ${SCENARIO_SERVER_NAME} migrate;

# TODO: All containers need to restart after installation
