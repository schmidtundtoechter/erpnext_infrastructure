#!/bin/bash

sudo chmod 777 /workspace
cd /workspace

# Copy SSH keys
if [ ! -d ~/.ssh/id_rsa ]; then
    if [ -d /workspace-local/.ssh ]; then
        echo "====================================="
        echo "Initializing the devcontainer: Copying SSH keys..."
        cp -r /workspace-local/.ssh ~/
        find ~/.ssh -type f -exec chmod 600 {} \;
        find ~/.ssh -type d -exec chmod 700 {} \;
        sleep 1
    else
        echo "No SSH keys found"
    fi
fi

# Clone erpnext_infrastructure
if [ ! -d erpnext_infrastructure ]; then
    echo "====================================="
    echo "Initializing the devcontainer: Cloning erpnext_infrastructure..."
    git clone git@github.com:schmidtundtoechter/erpnext_infrastructure.git
    sleep 1
fi

# Clone MIMS
if [ ! -d MIMS ]; then
    echo "====================================="
    echo "Initializing the devcontainer: Cloning MIMS..."
    git clone git@github.com:Cerulean-Circle-GmbH/MIMS.git
    sleep 1
fi
