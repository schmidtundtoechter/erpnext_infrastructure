#!/bin/bash

. .env

# Run in frontend-1 a set of commands with EOL
docker exec -i  ${PROJECT_NAME}-frontend-1 /bin/bash -s <<EOL
pwd
mkdir -p ~/.ssh;
echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa;
chmod 600 ~/.ssh/id_rsa;
if [ ! -d /home/frappe/frappe-bench/apps/test12 ]; then
    echo "App test12 does not exist - cloning";
    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" bench get-app git@github.com:larsmaeurer/test12.git;
else
    echo "App test12 already exists - pulling latest changes";
    cd /home/frappe/frappe-bench/apps/test12;
    GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" git pull;
fi;
rm -rf ~/.ssh

echo "Install test12 app and migrate";
bench --site $SITE install-app test12;
bench --site $SITE migrate;
EOL

./restart.sh