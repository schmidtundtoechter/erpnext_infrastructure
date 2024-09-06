#!/bin/bash

# Remove development
rm -rf development

# Clean repository
git reset --hard

# Remove untracked files and directories
git clean -fd
