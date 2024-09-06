#!/bin/bash

# Guide-to-Install-Frappe-ERPNext-in-Windows-11-Using-Docker
# A complete Guide to Install Frappe Bench in Windows 11 Using Docker and install Frappe/ERPNext Application

echo "### STEP 3: Create devcontainer and VS Code setup"
cp -r devcontainer-example .devcontainer
cp -r development/vscode-example development/.vscode
# Only on MaccOS with M1 or M2; ad check arm or amd platform
if [[ "$(docker version --format '{{.Server.Arch}}')" == "arm64" ]]; then
    echo "### Update devcontainer and docker-compose for M1/M2"
    mv .devcontainer/devcontainer.json .devcontainer/devcontainer.json.ORIG
    sed -e "s;linux/amd64;linux/arm64;g" .devcontainer/devcontainer.json.ORIG > .devcontainer/devcontainer.json
    mv .devcontainer/docker-compose.yml .devcontainer/docker-compose.yml.ORIG
    sed -e "s;linux/amd64;linux/arm64;g" .devcontainer/docker-compose.yml.ORIG > .devcontainer/docker-compose.yml
fi

echo "### STEP 4 Open vscode and install 'Dev Containers' extension"
echo "###  STEP 5 Open frappe_docker folder in VS Code."
echo "Launch the command, from Command Palette (Ctrl + Shift + P) Remote-Containers: Reopen in Container. You can also click in the bottom left corner to access the remote container menu."