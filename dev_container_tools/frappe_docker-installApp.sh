#!/bin/bash

# first argument needs to be github - link
if [ -z "$1" ]
  then
    echo "No argument supplied"
    exit 1
fi

# check that if it is a repository
if [[ $1 != *".git"* ]]; then
    echo "Not a repository"
    exit 1
fi

# Check wether bench process runs, if so, warn and exit
if [ -z "$(ps -ef | grep 'bench start' | grep -v grep)" ]; then
    echo "bench is not running"
else
    echo "bench is running, please stop it before running this script"
    exit 1
fi

# extract repository name from link
appName=$(echo $1 | rev | cut -d'/' -f 1 | rev | cut -d'.' -f 1) 

echo "first arg: $1"
echo "appName: $appName"

cd frappe-bench/

bench get-app $appName $1
bench --site d-code.localhost install-app $appName
bench --site d-code.localhost migrate
bench build

echo "bench jetzt neu starten: bench start"