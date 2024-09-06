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

echo "### STEP 6 Initialize frappe bench with frappe version 14 and Switch directory"
bench init --skip-redis-config-generation --frappe-branch version-14 frappe-bench
cd frappe-bench

echo "### STEP 7 Setup hosts"
# We need to tell bench to use the right containers instead of localhost. Run the following commands inside the container:
bench set-config -g db_host mariadb
bench set-config -g redis_cache redis://redis-cache:6379
bench set-config -g redis_queue redis://redis-queue:6379
#bench set-config -g redis_socketio redis://redis-socketio:6379
bench set-config -g redis_socketio redis://redis-cache:6379
# For any reason the above commands fail, set the values in common_site_config.json manually.
#{
#  "db_host": "mariadb",
#  "redis_cache": "redis://redis-cache:6379",
#  "redis_queue": "redis://redis-queue:6379",
#  "redis_socketio": "redis://redis-socketio:6379"
#}

echo "### STEP 8 Create a new site"
# sitename MUST end with .localhost for trying deployments locally.
# MariaDB root password: 123
bench new-site d-code.localhost --no-mariadb-socket 

echo "### STEP 9 Set bench developer mode on the new site"
bench --site d-code.localhost set-config developer_mode 1
bench --site d-code.localhost clear-cache   

echo "### STEP 10 Install ERPNext"
bench get-app --branch version-14 --resolve-deps erpnext
bench --site d-code.localhost install-app erpnext

echo "### STEP 11 Start Frappe bench"
bench start

echo "### You can now login with user Administrator and the password you choose when creating the site. Your website will now be accessible at location http://d-code.localhost:8000"
