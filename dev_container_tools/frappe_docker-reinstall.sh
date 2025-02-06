#!/bin/bash

# Guide-to-Install-Frappe-ERPNext-in-Windows-11-Using-Docker
# A complete Guide to Install Frappe Bench in Windows 11 Using Docker and install Frappe/ERPNext Application

sudo chown -R frappe:frappe /workspace

if [ -d /home/frappe/.ssh2 ]; then
    echo "### STEP 5.5 Copy ssh keys"
    cp -f /home/frappe/.ssh2/* /home/frappe/.ssh/
    chmod 600 /home/frappe/.ssh/*
fi

ERPNEXT_VERSION=15

echo "### STEP 6 Initialize frappe bench with frappe version ${ERPNEXT_VERSION} and Switch directory"
cd /workspace/development
bench init --skip-redis-config-generation --frappe-branch version-${ERPNEXT_VERSION} frappe-bench
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
bench get-app --branch version-${ERPNEXT_VERSION} --resolve-deps erpnext
bench --site d-code.localhost install-app erpnext

echo "### STEP 11 Start Frappe bench"
bench start

echo "### You can now login with user Administrator and the password you choose when creating the site. Your website will now be accessible at location http://d-code.localhost:8000"

