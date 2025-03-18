## Source setup
# This is the scenario component name which will be automatically filled. Default is ignored but must not be empty.
SCENARIO_SRC_COMPONENT=.
# This is the cache directory for downloaded files, like structr.zip or WODA-current.tar.gz
SCENARIO_SRC_CACHEDIR=~/.cache/MIMS-Scenarios
# This is the directory storing secrets for docker containers
SCENARIO_SRC_SECRETSDIR=/var/dev/MIMS-Scenarios/_secrets
## Server setup
# What is the server, the scenario will be deployed?
SCENARIO_SERVER_NAME=test.wo-da.de
# What is the SSH config the server can be connected with?
SCENARIO_SERVER_SSHCONFIG=WODA.test
# What is the scenarios root directory on the server?
SCENARIO_SERVER_CONFIGSDIR=/var/dev/MIMS-Scenarios
# Where to find the servers letsencrypt base dir?
SCENARIO_SERVER_CERTCONFIGDIR=/var/dev/EAMD.ucp/Scenarios/de/1blu/v36421/vhosts/de/wo-da/test/EAM/1_infrastructure/Docker/CertBot.v1.7.0/config
# Where to find the servers certificate?
SCENARIO_SERVER_CERTIFICATEDIR=/var/dev/EAMD.ucp/Scenarios/de/1blu/v36421/vhosts/de/wo-da/test/EAM/1_infrastructure/Docker/CertBot.v1.7.0/config/conf/live/test.wo-da.de
## Config data setup
# What is the path of the data volume (e.g. './data' or 'data-volume'; if it contains a '/', it is considered as a path, otherwise as a docker volume name)?
SCENARIO_DATA_VOLUME_1_PATH=./data
# Where to find the restore data (none - if not applicable)?
SCENARIO_DATA_VOLUME_1_RESTORESOURCE=none
# Is the data volume external (true or false; if not external, it will be deleted on down)?
SCENARIO_DATA_VOLUME_1_EXTERNAL=true
# What is the path used to store the db (e.g. './db' or 'db_storage'; if it contains a '/', it is considered as a path, otherwise as a docker volume name)?
#- path: env
# Is the volume external (true or false; if not external, it will be deleted on down)?
#external: true
# What is the path used to store redis (e.g. './redis' or 'redis_storage'; if it contains a '/', it is considered as a path, otherwise as a docker volume name)?
SCENARIO_DATA_VOLUME_2_PATH=apps
# Is the volume external (true or false; if not external, it will be deleted on down)?
SCENARIO_DATA_VOLUME_2_EXTERNAL=true
# What is the path used to store the db (e.g. './db' or 'db_storage'; if it contains a '/', it is considered as a path, otherwise as a docker volume name)?
SCENARIO_DATA_VOLUME_3_PATH=sites
# Is the volume external (true or false; if not external, it will be deleted on down)?
SCENARIO_DATA_VOLUME_3_EXTERNAL=true
# What is the path used to store redis (e.g. './redis' or 'redis_storage'; if it contains a '/', it is considered as a path, otherwise as a docker volume name)?
SCENARIO_DATA_VOLUME_4_PATH=logs
# Is the volume external (true or false; if not external, it will be deleted on down)?
SCENARIO_DATA_VOLUME_4_EXTERNAL=true
# What is the path used to store the db (e.g. './db' or 'db_storage'; if it contains a '/', it is considered as a path, otherwise as a docker volume name)?
SCENARIO_DATA_VOLUME_5_PATH=redis-queue-data
# Is the volume external (true or false; if not external, it will be deleted on down)?
SCENARIO_DATA_VOLUME_5_EXTERNAL=true
# What is the path used to store redis (e.g. './redis' or 'redis_storage'; if it contains a '/', it is considered as a path, otherwise as a docker volume name)?
SCENARIO_DATA_VOLUME_6_PATH=redis-cache-data
# Is the volume external (true or false; if not external, it will be deleted on down)?
SCENARIO_DATA_VOLUME_6_EXTERNAL=true
# What is the path used to store the db (e.g. './db' or 'db_storage'; if it contains a '/', it is considered as a path, otherwise as a docker volume name)?
SCENARIO_DATA_VOLUME_7_PATH=db-data
# Is the volume external (true or false; if not external, it will be deleted on down)?
SCENARIO_DATA_VOLUME_7_EXTERNAL=true
## Unique resources
# What is the http port of the docker container?
SCENARIO_RESOURCE_HTTPPORT=8080
## Traefik proxy setup
# What is the url?
SCENARIO_TRAEFIK_URL=erpnext.test.schmidtundtoechter.de
# Route to erpnext (does not yet work with erpnext)
SCENARIO_TRAEFIK_ROUTE=/
# Do you want to route this service via traefik?
SCENARIO_TRAEFIK_ENABLE=true
