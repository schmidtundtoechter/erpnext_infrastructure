#!/bin/bash

echo -- Remove directory ./development
rm -rf development

echo -- Clean repository
git reset --hard

echo -- Remove untracked files and directories
git clean -fd

echo -- Pull and go to main
git pull
git checkout main

