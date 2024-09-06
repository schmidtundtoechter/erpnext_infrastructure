#!/bin/bash

# Remove development
rm -rf development

# Clean repository
git reset --hard

# Remove untracked files and directories
git clean -fd

# Pull and go to main
git pull
git checkout main

