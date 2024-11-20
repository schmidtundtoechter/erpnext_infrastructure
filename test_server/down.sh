#!/bin/bash

. .env

docker compose -f $YAML_FILE -p $PROJECT_NAME down --volumes
